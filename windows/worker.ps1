# Odak Kilidi - arka plan servisi (Görev Zamanlayıcı ile SYSTEM olarak çalışır)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')

# Aynı anda tek kopya çalışsın
$mutex = New-Object System.Threading.Mutex($false, 'Global\OdakKilidiWorker')
if (-not $mutex.WaitOne(0)) { exit }

# Yasak saatlerde kapatılan "kapatma araçları" (Görev Zamanlayıcı / Hizmetler / Kayıt Defteri)
$GuardProcs = @('mmc', 'regedit')

function Write-Log([string]$msg) {
    try {
        if ((Test-Path $OK_Log) -and ((Get-Item $OK_Log).Length -gt 300KB)) {
            Move-Item $OK_Log "$OK_Log.old" -Force
        }
        Add-Content -Path $OK_Log -Value ("{0}  {1}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $OK_Inv), $msg) -Encoding UTF8
    } catch {}
}

# Ayar ekranından gelen istekleri işle. Durum değiştiyse $true.
function Invoke-Inbox($state) {
    $changed = $false
    $files = @(Get-ChildItem -Path $OK_Inbox -Filter 'req-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    foreach ($f in $files) {
        $req = $null
        try { $req = Get-Content -Path $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
        Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
        if ($null -eq $req) { continue }
        $result = 'BILINMEYEN'
        switch ([string]$req.type) {
            'save' {
                $new = ConvertTo-Config $req.config
                $first = (-not $state.savedOnce) -or (@($state.active.rules).Count -eq 0)
                if ($first -or (Test-StricterOrEqual $new $state.active)) {
                    $state.active = $new
                    $state.pending = $null
                    $state.pendingDate = $null
                    $state.savedOnce = $true
                    $result = 'OK_NOW'
                } else {
                    $state.pending = $new
                    $state.pendingDate = Get-Tomorrow
                    $result = 'OK_TOMORROW'
                }
            }
            'startSession' {
                $min = [int]$req.minutes
                $now = Get-Date
                $start = if ($req.start) { ConvertFrom-IsoTime ([string]$req.start) } else { $now }
                if ($null -eq $start -or $start -lt $now.AddMinutes(-2)) { $start = $now }
                $sess = ConvertTo-Session ([pscustomobject]@{ start = ''; end = ''; apps = $req.apps; sites = $req.sites })
                if ($min -ge 5 -and $min -le 720 -and $start -le $now.AddDays(1) -and ($sess.apps.Count + $sess.sites.Count) -gt 0) {
                    $sess.start = $start.ToString('o', $OK_Inv)
                    $sess.end = $start.AddMinutes($min).ToString('o', $OK_Inv)
                    $alive = Get-AliveSessions $state
                    $state.sessions = @($alive) + @($sess)
                    $state.lastSession = $sess
                    $result = 'OK'
                } else {
                    $result = 'GECERSIZ'
                }
            }
            'cancelPending' { $state.pending = $null; $state.pendingDate = $null; $result = 'OK' }
            'unlock'        { $state.unlockDate = Get-Tomorrow; $result = 'OK' }
            'cancelUnlock'  { $state.unlockDate = $null; $result = 'OK' }
        }
        $state.lastRequestId = [string]$req.id
        $state.lastResult = $result
        Write-Log "istek: $($req.type) -> $result"
        $changed = $true
    }
    return $changed
}

# Tarihe bağlı geçişler. Durum değiştiyse $true.
function Update-Dates($state) {
    $today = Get-Today
    $changed = $false
    if ($state.pendingDate -and ($state.pendingDate -le $today)) {
        if ($null -ne $state.pending) { $state.active = $state.pending }
        $state.pending = $null
        $state.pendingDate = $null
        Write-Log 'bekleyen degisiklik gecerli oldu'
        $changed = $true
    }
    $alive = Get-AliveSessions $state
    if ($alive.Count -ne @($state.sessions | Where-Object { $null -ne $_ }).Count) {
        $state.sessions = $alive
        $changed = $true
    }
    if ($state.unlockDate -and ($state.unlockDate -lt $today)) {
        $state.unlockDate = $null
        $changed = $true
    }
    return $changed
}

$lastBlocked = $null
$lastHeartbeat = [datetime]::MinValue

Write-Log 'servis basladi'

while ($true) {
    try {
        $state = Read-OKState
        if ($null -ne $state) {
            $dirty = Invoke-Inbox $state
            if (Update-Dates $state) { $dirty = $true }
            if ($dirty) { Save-OKState $state }

            $bs = Get-BlockState $state.active (Get-WeekMinute) (Get-ActiveSessions $state)
            $blocked = ($bs.procs.Count + $bs.sites.Count) -gt 0

            if ($blocked) {
                foreach ($p in $bs.procs) {
                    Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                }
                if ($state.unlockDate -ne (Get-Today)) {
                    foreach ($p in $GuardProcs) {
                        Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            $sites = $bs.sites

            try { if (Set-HostsBlock $sites) { Write-Log "hosts guncellendi ($($sites.Count) site)" } } catch { Write-Log "hosts hatasi: $_" }
            try { if (Set-BrowserPolicy $sites) { Write-Log "tarayici politikasi guncellendi ($($sites.Count) site)" } } catch { Write-Log "politika hatasi: $_" }

            if ($blocked -ne $lastBlocked) {
                Write-Log ("durum: " + $(if ($blocked) { 'YASAK' } else { 'serbest' }))
                $lastBlocked = $blocked
            }
        }
        if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 60) {
            Set-Content -Path $OK_Heartbeat -Value (Get-Date).ToString('o', $OK_Inv) -Encoding ASCII
            $lastHeartbeat = Get-Date
        }
    } catch {
        Write-Log "HATA: $_"
    }
    Start-Sleep -Seconds 3
}
