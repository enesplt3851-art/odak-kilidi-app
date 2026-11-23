# Odak Kilidi - Windows kurulumu (yönetici olarak çalışmalı; Kur.bat bunu otomatik yapar)
$ErrorActionPreference = 'Stop'

$principalCheck = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Bu kurulum yonetici olarak calismali. Kur.bat dosyasini kullan.' -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot 'common.ps1')
$dir = $OK_Base
$app = Join-Path $dir 'app'
$TaskName = 'OdakKilidi'

Write-Host '== Odak Kilidi kuruluyor ==' -ForegroundColor Cyan

# Güncelleme ise: önce yazma izni al ve eski servisi durdur
if (Test-Path $dir) {
    & icacls.exe $dir /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q | Out-Null
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*OdakKilidi*worker.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
}

New-Item -ItemType Directory -Force -Path $dir, $app, $OK_Inbox | Out-Null
foreach ($f in 'common.ps1', 'worker.ps1', 'Ayarlar.ps1', 'uninstall.ps1') {
    Copy-Item -Path (Join-Path $PSScriptRoot $f) -Destination (Join-Path $app $f) -Force
    Unblock-File -Path (Join-Path $app $f) -ErrorAction SilentlyContinue
}

# İlk kurulumda varsayılan ayarlar (güncellemede mevcut ayarlar korunur)
if (-not (Test-Path $OK_State)) {
    Save-OKState (Normalize-State $null)
    Write-Host 'Varsayilan ayarlar olusturuldu.'
} else {
    Write-Host 'Mevcut ayarlar korundu.'
}

# İzinler: SYSTEM tam, Yöneticiler ve Kullanıcılar sadece okuma. Ayar ekranı sadece inbox klasörüne yazabilir.
& icacls.exe $dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)RX' '*S-1-5-32-545:(OI)(CI)RX' /Q | Out-Null
& icacls.exe (Join-Path $dir '*') /reset /T /C /Q | Out-Null
& icacls.exe $OK_Inbox /grant '*S-1-5-32-545:(OI)(CI)M' /Q | Out-Null

# Görev Zamanlayıcı: SYSTEM olarak, açılışta + her dakika (kapanırsa tekrar başlar)
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $app 'worker.ps1'))
$t1 = New-ScheduledTaskTrigger -AtStartup
$t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $t1, $t2 -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Host 'Arka plan servisi baslatildi.'

# Ayarlar kısayolu (masaüstü + Başlat menüsü)
$guiArgs = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $app 'Ayarlar.ps1'))
$wsh = New-Object -ComObject WScript.Shell
$targets = @(
    (Join-Path $env:PUBLIC 'Desktop\Odak Kilidi.lnk'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Odak Kilidi.lnk')
)
foreach ($lnkPath in $targets) {
    $lnk = $wsh.CreateShortcut($lnkPath)
    $lnk.TargetPath = $ps
    $lnk.Arguments = $guiArgs
    $lnk.IconLocation = "$env:SystemRoot\System32\imageres.dll,54"
    $lnk.Description = 'Odak Kilidi ayarlari'
    $lnk.Save()
}

Write-Host ''
Write-Host 'Kurulum tamam! Masaustundeki "Odak Kilidi" kisayolundan yasak saatleri ayarla.' -ForegroundColor Green
