# Odak Kilidi - kaldırma (sadece "kaldırma izni" gününde çalışır)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms

$principalCheck = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show('Kaldırma yönetici olarak çalışmalı.', 'Odak Kilidi') | Out-Null
    exit 1
}

$commonPath = Join-Path $PSScriptRoot 'common.ps1'
if (-not (Test-Path $commonPath)) { $commonPath = Join-Path $env:ProgramData 'OdakKilidi\app\common.ps1' }
. $commonPath

$state = Read-OKState
if ($null -eq $state -or $state.unlockDate -ne (Get-Today)) {
    $msg = 'Bugün kaldırma izni günü değil.' + [Environment]::NewLine + [Environment]::NewLine +
           'Odak Kilidi ayarlarından "Kaldırma izni iste" butonuna bas. İzin ertesi gün, bir gün boyunca açılır; o gün tekrar dene.'
    if ($state -and $state.unlockDate) { $msg += [Environment]::NewLine + [Environment]::NewLine + "İzin tarihi: $($state.unlockDate)" }
    [System.Windows.Forms.MessageBox]::Show($msg, 'Odak Kilidi', 'OK', 'Warning') | Out-Null
    exit 2
}

$ok = [System.Windows.Forms.MessageBox]::Show('Odak Kilidi tamamen kaldırılsın mı?', 'Odak Kilidi', 'YesNo', 'Question')
if ($ok -ne 'Yes') { exit 0 }

# 1) Servisi durdur ve sil
Stop-ScheduledTask -TaskName 'OdakKilidi' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'OdakKilidi' -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*OdakKilidi*worker.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2) Engelleri temizle
try { [void](Set-HostsBlock @()) } catch {}
try { [void](Set-BrowserPolicy @()) } catch {}

# 3) Kısayollar ve dosyalar
Remove-Item (Join-Path $env:PUBLIC 'Desktop\Odak Kilidi.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Odak Kilidi.lnk') -Force -ErrorAction SilentlyContinue
& icacls.exe $OK_Base /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q | Out-Null
Set-Location $env:SystemRoot
Remove-Item -Path $OK_Base -Recurse -Force -ErrorAction SilentlyContinue

[System.Windows.Forms.MessageBox]::Show('Odak Kilidi kaldırıldı.', 'Odak Kilidi') | Out-Null
