# Odak Kilidi - ortak kurallar (worker, ayarlar ve kaldırma tarafından kullanılır)

$Global:OK_Base      = Join-Path $env:ProgramData 'OdakKilidi'
$Global:OK_State     = Join-Path $OK_Base 'state.json'
$Global:OK_Inbox     = Join-Path $OK_Base 'inbox'
$Global:OK_Heartbeat = Join-Path $OK_Base 'heartbeat.txt'
$Global:OK_Log       = Join-Path $OK_Base 'worker.log'
$Global:OK_Hosts     = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$Global:OK_Policies  = @(
    'SOFTWARE\Policies\Google\Chrome\URLBlocklist',
    'SOFTWARE\Policies\Microsoft\Edge\URLBlocklist',
    'SOFTWARE\Policies\BraveSoftware\Brave\URLBlocklist'
)
$Global:OK_Inv  = [Globalization.CultureInfo]::InvariantCulture
$Global:OK_Week = 10080
$Global:OK_DayNames = @('Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz')

# Favori platformlar: site + Windows program adı birlikte
$Global:OK_Presets = @(
    [pscustomobject]@{ name = 'Instagram';   sites = @('instagram.com');           procs = @('instagram') },
    [pscustomobject]@{ name = 'YouTube';     sites = @('youtube.com', 'youtu.be'); procs = @() },
    [pscustomobject]@{ name = 'TikTok';      sites = @('tiktok.com');              procs = @('tiktok') },
    [pscustomobject]@{ name = 'X (Twitter)'; sites = @('x.com', 'twitter.com');    procs = @() },
    [pscustomobject]@{ name = 'Facebook';    sites = @('facebook.com');            procs = @('facebook') },
    [pscustomobject]@{ name = 'Reddit';      sites = @('reddit.com');              procs = @() },
    [pscustomobject]@{ name = 'Twitch';      sites = @('twitch.tv');               procs = @() },
    [pscustomobject]@{ name = 'Netflix';     sites = @('netflix.com');             procs = @() },
    [pscustomobject]@{ name = 'Snapchat';    sites = @('snapchat.com');            procs = @() },
    [pscustomobject]@{ name = 'Discord';     sites = @('discord.com');             procs = @('discord') },
    [pscustomobject]@{ name = 'Pinterest';   sites = @('pinterest.com');           procs = @() },
    [pscustomobject]@{ name = 'WhatsApp';    sites = @('web.whatsapp.com');        procs = @('whatsapp') }
)

# ---------- Yardımcılar ----------

# Temiz bir string dizisi döndürür (boşları atar). Baştaki virgül: PowerShell diziyi açmasın diye.
function L($x) {
    , [string[]]@($x | Where-Object { $null -ne $_ -and "$_".Trim() -ne '' } | ForEach-Object { "$_".Trim() })
}

function Get-Today    { (Get-Date).ToString('yyyy-MM-dd', $OK_Inv) }
function Get-Tomorrow { (Get-Date).AddDays(1).ToString('yyyy-MM-dd', $OK_Inv) }

# Haftanın dakikası: Pazartesi 00:00 = 0
function Get-WeekMinute {
    $n = Get-Date
    $dow = ([int]$n.DayOfWeek + 6) % 7
    return ($dow * 1440 + $n.Hour * 60 + $n.Minute)
}

function Format-Min([int]$m) {
    $m = (($m % 1440) + 1440) % 1440
    return ('{0:D2}:{1:D2}' -f [int][math]::Floor($m / 60), ($m % 60))
}

function Format-Duration([int]$min) {
    $d = [int][math]::Floor($min / 1440); $h = [int][math]::Floor(($min % 1440) / 60); $m = $min % 60
    $p = @()
    if ($d -gt 0) { $p += "$d gün" }
    if ($h -gt 0) { $p += "$h sa" }
    if ($m -gt 0 -or $p.Count -eq 0) { $p += "$m dk" }
    return ($p -join ' ')
}

# Haftanın dakikası -> bugünse "09:00", değilse "Sal 09:00"
function Format-WeekMinute([int]$wm, [int]$nowWm) {
    $day = [int][math]::Floor($wm / 1440) % 7
    $today = [int][math]::Floor($nowWm / 1440) % 7
    if ($day -eq $today) { return (Format-Min $wm) }
    return ("{0} {1}" -f $OK_DayNames[$day], (Format-Min $wm))
}

function Format-Range($g) {
    if ($g.s -eq $g.e) { return 'Tüm gün' }
    return ("{0}–{1}" -f (Format-Min $g.s), (Format-Min $g.e))
}

function Format-Days($days) {
    $d = @($days)
    $all = -not ($d -contains $false)
    $wk = $d[0] -and $d[1] -and $d[2] -and $d[3] -and $d[4] -and -not $d[5] -and -not $d[6]
    $we = -not ($d[0] -or $d[1] -or $d[2] -or $d[3] -or $d[4]) -and $d[5] -and $d[6]
    if ($all) { return 'Her gün' }
    if ($wk) { return 'Hafta içi' }
    if ($we) { return 'Hafta sonu' }
    $names = for ($i = 0; $i -lt 7; $i++) { if ($d[$i]) { $OK_DayNames[$i] } }
    if (-not $names) { return 'Gün yok' }
    return (@($names) -join ' ')
}

# ---------- Veri modeli ----------

function New-Range([int]$s, [int]$e) { [pscustomobject]@{ s = $s; e = $e } }

function New-RuleId { ([guid]::NewGuid().ToString()).Substring(0, 8) }

function ConvertTo-Rule($o) {
    $days = New-Object bool[] 7
    $src = @($o.days)
    for ($i = 0; $i -lt 7; $i++) { $days[$i] = if ($null -eq $o.days -or $i -ge $src.Count) { $true } else { [bool]$src[$i] } }
    $ranges = @()
    if ($null -ne $o.ranges) {
        $ranges = @($o.ranges | Where-Object { $null -ne $_ } | ForEach-Object { New-Range ([int]$_.s) ([int]$_.e) })
    }
    $kind = if ([string]$o.kind -eq 'ders') { 'ders' } else { 'rutin' }
    $id = if ($o.id) { [string]$o.id } else { New-RuleId }
    $name = if ($o.name) { [string]$o.name } else { 'Kural' }
    [pscustomobject]@{
        id = $id; name = $name; kind = $kind; days = $days; ranges = $ranges
        apps = (L $o.apps); sites = (L $o.sites)
    }
}

function New-DefaultConfig { [pscustomobject]@{ rules = @() } }

function ConvertTo-Config($o) {
    if ($null -eq $o) { return (New-DefaultConfig) }
    if ($null -ne $o.PSObject.Properties['rules'] -or ($o -is [hashtable] -and $o.ContainsKey('rules'))) {
        $rules = @(@($o.rules) | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-Rule $_ })
        return [pscustomobject]@{ rules = $rules }
    }
    # Eski sürümden geçiş: tek bir "Genel" rutin kural
    $apps = L $o.apps; $sites = L $o.sites
    $rg = @()
    if ($null -ne $o.ranges) { $rg = @($o.ranges | Where-Object { $null -ne $_ } | ForEach-Object { New-Range ([int]$_.s) (([int]$_.e) % 1440) }) }
    if ($rg.Count -eq 0 -and $apps.Count -eq 0 -and $sites.Count -eq 0) { return (New-DefaultConfig) }
    $r = ConvertTo-Rule ([pscustomobject]@{ id = (New-RuleId); name = 'Genel'; kind = 'rutin'; days = $null; ranges = @(); apps = $apps; sites = $sites })
    $r.ranges = $rg
    return [pscustomobject]@{ rules = @($r) }
}

# İstek dosyasına yazmak için düz hashtable
function ConvertTo-RuleHash($r) {
    @{
        id = [string]$r.id; name = [string]$r.name; kind = [string]$r.kind
        days = [bool[]]@($r.days)
        ranges = @(@($r.ranges) | Where-Object { $null -ne $_ } | ForEach-Object { @{ s = [int]$_.s; e = [int]$_.e } })
        apps = [string[]](L $r.apps); sites = [string[]](L $r.sites)
    }
}

function Normalize-State($raw) {
    $s = [pscustomobject]@{
        savedOnce     = $false
        active        = (New-DefaultConfig)
        pending       = $null
        pendingDate   = $null
        unlockDate    = $null
        sessionEnd    = $null
        lastRequestId = $null
        lastResult    = $null
    }
    if ($null -ne $raw) {
        $s.savedOnce = [bool]$raw.savedOnce
        if ($null -ne $raw.active)  { $s.active  = ConvertTo-Config $raw.active }
        if ($null -ne $raw.pending) { $s.pending = ConvertTo-Config $raw.pending }
        if ($raw.pendingDate)   { $s.pendingDate   = [string]$raw.pendingDate }
        if ($raw.unlockDate)    { $s.unlockDate    = [string]$raw.unlockDate }
        if ($raw.sessionEnd)    { $s.sessionEnd    = [string]$raw.sessionEnd }
        if ($raw.lastRequestId) { $s.lastRequestId = [string]$raw.lastRequestId }
        if ($raw.lastResult)    { $s.lastResult    = [string]$raw.lastResult }
    }
    return $s
}

function Read-OKState {
    if (-not (Test-Path $OK_State)) { return (Normalize-State $null) }
    try {
        $raw = Get-Content -Path $OK_State -Raw -Encoding UTF8 | ConvertFrom-Json
        return (Normalize-State $raw)
    } catch {
        return $null
    }
}

function Save-OKState($s) {
    $json = $s | ConvertTo-Json -Depth 8
    $tmp = "$OK_State.tmp"
    Set-Content -Path $tmp -Value $json -Encoding UTF8
    Move-Item -Path $tmp -Destination $OK_State -Force
}

# ---------- Ders modu ----------

function Get-SessionEnd($state) {
    if (-not $state.sessionEnd) { return $null }
    try { return [datetime]::Parse($state.sessionEnd, $OK_Inv, [Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime() } catch { return $null }
}

function Test-SessionActive($state) {
    $e = Get-SessionEnd $state
    return ($null -ne $e -and $e -gt (Get-Date))
}

# ---------- Zaman kuralları ----------

function Get-RangeLen($g) {
    $d = ((([int]$g.e - [int]$g.s) % 1440) + 1440) % 1440
    if ($d -eq 0) { return 1440 }
    return $d
}

# Kural, haftanın bu dakikasında yasak mı? (Aralık başladığı güne aittir.)
function Test-RuleCovers($r, [int]$wm) {
    for ($d = 0; $d -lt 7; $d++) {
        if (-not $r.days[$d]) { continue }
        foreach ($g in @($r.ranges)) {
            if ($null -eq $g) { continue }
            $off = ((($wm - ($d * 1440 + $g.s)) % $OK_Week) + $OK_Week) % $OK_Week
            if ($off -lt (Get-RangeLen $g)) { return $true }
        }
    }
    return $false
}

# Kural kaç dakika sonra serbest kalır? (Şu an aktif değilse 0, hiç bitmiyorsa -1)
function Get-RuleFreeIn($r, [int]$wm) {
    $t = 0
    while ($t -lt $OK_Week) {
        $m = ($wm + $t) % $OK_Week
        $best = -1
        for ($d = 0; $d -lt 7; $d++) {
            if (-not $r.days[$d]) { continue }
            foreach ($g in @($r.ranges)) {
                if ($null -eq $g) { continue }
                $len = Get-RangeLen $g
                $off = ((($m - ($d * 1440 + $g.s)) % $OK_Week) + $OK_Week) % $OK_Week
                if ($off -lt $len -and ($len - $off) -gt $best) { $best = $len - $off }
            }
        }
        if ($best -lt 0) { return $t }
        $t += $best
    }
    return -1
}

# Kural en erken kaç dakika sonra başlar? Başlangıç yoksa -1
function Get-RuleStartsIn($r, [int]$wm) {
    $min = -1
    for ($d = 0; $d -lt 7; $d++) {
        if (-not $r.days[$d]) { continue }
        foreach ($g in @($r.ranges)) {
            if ($null -eq $g) { continue }
            $delta = ((($d * 1440 + $g.s) - $wm) % $OK_Week + $OK_Week) % $OK_Week
            if ($delta -eq 0) { continue }
            if ($min -lt 0 -or $delta -lt $min) { $min = $delta }
        }
    }
    return $min
}

function Get-RuleMask($r) {
    $b = New-Object System.Collections.BitArray $OK_Week
    for ($d = 0; $d -lt 7; $d++) {
        if (-not $r.days[$d]) { continue }
        foreach ($g in @($r.ranges)) {
            if ($null -eq $g) { continue }
            $st = $d * 1440 + $g.s
            $len = Get-RangeLen $g
            for ($i = 0; $i -lt $len; $i++) { $b.Set(($st + $i) % $OK_Week, $true) }
        }
    }
    return , $b
}

function Get-RuleTargets($r) {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($a in (L $r.apps))  { $list.Add("a:$a") }
    foreach ($s in (L $r.sites)) { $list.Add("s:$s") }
    return , $list.ToArray()
}

function Get-DersTargets($cfg) {
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($r in @($cfg.rules)) {
        if ($null -eq $r -or $r.kind -ne 'ders') { continue }
        foreach ($t in (Get-RuleTargets $r)) { [void]$set.Add($t) }
    }
    return , [string[]]@($set)
}

# Yeni ayar eskisinden daha sıkı (ya da aynı) mı? Öyleyse hemen uygulanabilir.
function Test-StricterOrEqual($new, $old) {
    $nd = Get-DersTargets $new
    foreach ($t in (Get-DersTargets $old)) { if ($nd -notcontains $t) { return $false } }

    $oldRules = @(@($old.rules) | Where-Object { $null -ne $_ })
    $newRules = @(@($new.rules) | Where-Object { $null -ne $_ })
    $oldMasks = @($oldRules | ForEach-Object { , (Get-RuleMask $_) })
    $newMasks = @($newRules | ForEach-Object { , (Get-RuleMask $_) })
    $oldT = @($oldRules | ForEach-Object { , (Get-RuleTargets $_) })
    $newT = @($newRules | ForEach-Object { , (Get-RuleTargets $_) })

    $all = New-Object System.Collections.Generic.HashSet[string]
    foreach ($ts in $oldT) { foreach ($t in $ts) { [void]$all.Add($t) } }

    foreach ($t in $all) {
        $o = New-Object System.Collections.BitArray $OK_Week
        for ($i = 0; $i -lt $oldRules.Count; $i++) { if ($oldT[$i] -contains $t) { [void]$o.Or($oldMasks[$i]) } }
        $n = New-Object System.Collections.BitArray $OK_Week
        for ($i = 0; $i -lt $newRules.Count; $i++) { if ($newT[$i] -contains $t) { [void]$n.Or($newMasks[$i]) } }
        [void]$n.Not()
        [void]$o.And($n)
        $ints = New-Object int[] 315
        $o.CopyTo($ints, 0)
        foreach ($x in $ints) { if ($x -ne 0) { return $false } }
    }
    return $true
}

# Şu an neler engelli? -> procs, sites, rules (aktif kural adları)
function Get-BlockState($cfg, [int]$wm, [bool]$session) {
    $procs = New-Object System.Collections.Generic.HashSet[string]
    $sites = New-Object System.Collections.Generic.HashSet[string]
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($cfg.rules)) {
        if ($null -eq $r) { continue }
        $on = Test-RuleCovers $r $wm
        if ($on) { $names.Add([string]$r.name) }
        if ($on -or ($session -and $r.kind -eq 'ders')) {
            foreach ($a in (L $r.apps))  { [void]$procs.Add($a) }
            foreach ($s in (L $r.sites)) { [void]$sites.Add($s) }
        }
    }
    [pscustomobject]@{ procs = [string[]]@($procs); sites = [string[]]@($sites); rules = [string[]]@($names) }
}

# "https://www.YouTube.com/watch?v=x" -> "youtube.com"
function Get-NormalHost([string]$s) {
    $x = $s.Trim().ToLowerInvariant()
    $i = $x.IndexOf('://'); if ($i -ge 0) { $x = $x.Substring($i + 3) }
    $x = ($x -split '[/?#]')[0]
    $i = $x.LastIndexOf('@'); if ($i -ge 0) { $x = $x.Substring($i + 1) }
    $x = ($x -split ':')[0]
    $x = $x.TrimEnd('.')
    if ($x.StartsWith('www.')) { $x = $x.Substring(4) }
    return $x
}

# "Discord.exe" -> "discord"
function Get-ProcName([string]$s) {
    $x = $s.Trim().ToLowerInvariant()
    if ($x.EndsWith('.exe')) { $x = $x.Substring(0, $x.Length - 4) }
    return $x
}

# ---------- Engelleme uygulayıcıları ----------

$Global:OK_HostsBegin = '# >>> OdakKilidi (elle duzenlemeyin)'
$Global:OK_HostsEnd   = '# <<< OdakKilidi'

# Sadece değişiklik varsa yazar. Değişiklik olduysa $true döner.
function Set-HostsBlock($sites) {
    $sites = L $sites
    $lines = [IO.File]::ReadAllLines($OK_Hosts)
    $out = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($l in $lines) {
        if ($l -eq $OK_HostsBegin) { $inside = $true; continue }
        if ($l -eq $OK_HostsEnd) { $inside = $false; continue }
        if (-not $inside) { $out.Add($l) }
    }
    while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '') { $out.RemoveAt($out.Count - 1) }
    if ($sites.Count -gt 0) {
        $out.Add('')
        $out.Add($OK_HostsBegin)
        foreach ($s in $sites) {
            foreach ($h in @($s, "www.$s", "m.$s")) {
                $out.Add("0.0.0.0 $h")
                $out.Add(":: $h")
            }
        }
        $out.Add($OK_HostsEnd)
    }
    $new = ($out -join "`r`n") + "`r`n"
    $old = [IO.File]::ReadAllText($OK_Hosts)
    if ($new -cne $old) {
        [IO.File]::WriteAllText($OK_Hosts, $new, [Text.Encoding]::ASCII)
        & ipconfig.exe /flushdns | Out-Null
        return $true
    }
    return $false
}

# Chrome / Edge / Brave yönetici politikası: URLBlocklist. Değişiklik olduysa $true.
function Set-BrowserPolicy($sites) {
    $want = L $sites
    $hklm = [Microsoft.Win32.Registry]::LocalMachine
    $changed = $false
    foreach ($path in $OK_Policies) {
        $have = @()
        $k = $hklm.OpenSubKey($path)
        if ($null -ne $k) {
            $names = @($k.GetValueNames() | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ })
            $have = @($names | ForEach-Object { [string]$k.GetValue($_) })
            $k.Close()
        }
        if ((@($want) -join '|') -ceq (@($have) -join '|')) { continue }
        try { $hklm.DeleteSubKeyTree($path, $false) } catch {}
        if ($want.Count -gt 0) {
            $nk = $hklm.CreateSubKey($path)
            $i = 1
            foreach ($s in $want) {
                $nk.SetValue("$i", $s, [Microsoft.Win32.RegistryValueKind]::String)
                $i++
            }
            $nk.Close()
        }
        $changed = $true
    }
    if ($changed) {
        # Tarayıcıların politikayı hemen yeniden okuması için
        Start-Process -FilePath 'gpupdate.exe' -ArgumentList '/target:computer', '/force' -WindowStyle Hidden
    }
    return $changed
}
