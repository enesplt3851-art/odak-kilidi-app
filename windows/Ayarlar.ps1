# Odak Kilidi - ayar penceresi (yönetici gerekmez)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'common.ps1')

$Red    = [System.Drawing.Color]::FromArgb(197, 48, 48)
$Green  = [System.Drawing.Color]::FromArgb(47, 133, 90)
$Amber  = [System.Drawing.Color]::FromArgb(183, 121, 31)
$Navy   = [System.Drawing.Color]::FromArgb(31, 42, 68)
$Accent = [System.Drawing.Color]::FromArgb(59, 91, 219)
$Gray   = [System.Drawing.Color]::DimGray
$FontN = New-Object System.Drawing.Font('Segoe UI', 10)
$FontB = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$FontH = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)

$DurLabels = @('25 dk', '45 dk', '1 saat', '1,5 saat', '2 saat', '3 saat', '4 saat')
$DurMins   = @(25, 45, 60, 90, 120, 180, 240)

$script:St = $null          # son okunan durum
$script:Rules = @()         # listede gösterilen (düzenlenebilir) kurallar

function Show-Msg([string]$text, [string]$icon = 'Information') {
    [System.Windows.Forms.MessageBox]::Show($text, 'Odak Kilidi', 'OK', $icon) | Out-Null
}

function Ask-YesNo([string]$text) {
    return ([System.Windows.Forms.MessageBox]::Show($text, 'Odak Kilidi', 'YesNo', 'Question') -eq 'Yes')
}

# Servise istek gönder ve cevabını bekle
function Send-Request([hashtable]$req) {
    $id = [guid]::NewGuid().ToString()
    $req.id = $id
    $tmp = Join-Path $OK_Inbox "tmp-$id.json"
    try {
        Set-Content -Path $tmp -Value ($req | ConvertTo-Json -Depth 8) -Encoding UTF8
        Rename-Item -Path $tmp -NewName "req-$id.json"
    } catch {
        Show-Msg "İstek yazılamadı: $_" 'Error'
        return $null
    }
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
        [System.Windows.Forms.Application]::DoEvents()
        $st = Read-OKState
        if ($st -and $st.lastRequestId -eq $id) { return $st.lastResult }
    }
    return $null
}

function Test-WorkerAlive {
    try {
        $t = [datetime]::Parse((Get-Content $OK_Heartbeat -Raw).Trim(), $OK_Inv, [Globalization.DateTimeStyles]::RoundtripKind)
        return (((Get-Date) - $t.ToLocalTime()).TotalMinutes -lt 3)
    } catch { return $false }
}

function Get-TargetsText($r) {
    $names = New-Object System.Collections.Generic.List[string]
    $apps = L $r.apps; $sites = L $r.sites
    foreach ($p in $OK_Presets) {
        $hit = $false
        foreach ($s in $p.sites) { if ($sites -contains $s) { $hit = $true } }
        foreach ($a in $p.procs) { if ($apps -contains $a) { $hit = $true } }
        if ($hit) { $names.Add($p.name) }
    }
    $presetSites = @($OK_Presets | ForEach-Object { $_.sites } | ForEach-Object { $_ })
    $presetProcs = @($OK_Presets | ForEach-Object { $_.procs } | ForEach-Object { $_ })
    foreach ($a in $apps)  { if ($presetProcs -notcontains $a) { $names.Add("$a (program)") } }
    foreach ($s in $sites) { if ($presetSites -notcontains $s) { $names.Add($s) } }
    if ($names.Count -eq 0) { return '-' }
    return ($names -join ', ')
}

# Kaydet: tüm kural listesini servise gönder
function Save-Rules($rules) {
    $cfg = @{ rules = @(@($rules) | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-RuleHash $_ }) }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $res = Send-Request @{ type = 'save'; config = $cfg }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    switch ($res) {
        'OK_NOW'      { Show-Msg 'Kaydedildi. Değişiklik hemen geçerli oldu.' }
        'OK_TOMORROW' { Show-Msg "Bu değişiklik kısıtlamayı azalttığı için $(Get-Tomorrow) tarihinde (gece 00:00'dan sonra) geçerli olacak. Bugün eski kurallar devam ediyor." }
        default       { Show-Msg 'Arka plan servisi yanıt vermedi. Bilgisayarı yeniden başlat ya da Kur.bat''ı tekrar çalıştır.' 'Error' }
    }
    Update-Form
}

# =====================================================================
#  Kural düzenleme penceresi
# =====================================================================
function Show-RuleEditor($rule) {
    $script:Ed = @{ ranges = New-Object System.Collections.ArrayList; result = $null }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = if ($null -eq $rule) { 'Yeni kural' } else { 'Kuralı düzenle' }
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 705)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.Font = $FontN
    $dlg.BackColor = [System.Drawing.Color]::White

    function D-Label($text, $x, $y, $w, $font = $FontB, $color = $Navy) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y)
        $l.Size = New-Object System.Drawing.Size($w, 20); $l.Font = $font; $l.ForeColor = $color
        $dlg.Controls.Add($l)
    }

    # Ad
    D-Label 'Kural adı' 15 12 300
    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(15, 34); $txtName.Size = New-Object System.Drawing.Size(530, 26)
    $dlg.Controls.Add($txtName)

    # Tür
    $rbRutin = New-Object System.Windows.Forms.RadioButton
    $rbRutin.Text = 'Rutin (her hafta otomatik)'; $rbRutin.Location = New-Object System.Drawing.Point(15, 70); $rbRutin.Size = New-Object System.Drawing.Size(230, 24)
    $rbDers = New-Object System.Windows.Forms.RadioButton
    $rbDers.Text = 'Ders (Ders başlat butonu + istersen saat)'; $rbDers.Location = New-Object System.Drawing.Point(250, 70); $rbDers.Size = New-Object System.Drawing.Size(300, 24)
    $dlg.Controls.AddRange(@($rbRutin, $rbDers))

    # Günler
    D-Label 'Günler' 15 104 300
    $dayChecks = @()
    for ($i = 0; $i -lt 7; $i++) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $OK_DayNames[$i]; $c.Location = New-Object System.Drawing.Point((15 + $i * 76), 126); $c.Size = New-Object System.Drawing.Size(72, 24)
        $dlg.Controls.Add($c); $dayChecks += $c
    }
    $script:Ed.dayChecks = $dayChecks
    $bAll = New-Object System.Windows.Forms.Button; $bAll.Text = 'Her gün'; $bAll.Location = New-Object System.Drawing.Point(15, 154); $bAll.Size = New-Object System.Drawing.Size(100, 28)
    $bWk  = New-Object System.Windows.Forms.Button; $bWk.Text = 'Hafta içi'; $bWk.Location = New-Object System.Drawing.Point(122, 154); $bWk.Size = New-Object System.Drawing.Size(100, 28)
    $bWe  = New-Object System.Windows.Forms.Button; $bWe.Text = 'Hafta sonu'; $bWe.Location = New-Object System.Drawing.Point(229, 154); $bWe.Size = New-Object System.Drawing.Size(100, 28)
    $bAll.Add_Click({ for ($i = 0; $i -lt 7; $i++) { $script:Ed.dayChecks[$i].Checked = $true } })
    $bWk.Add_Click({ for ($i = 0; $i -lt 7; $i++) { $script:Ed.dayChecks[$i].Checked = ($i -lt 5) } })
    $bWe.Add_Click({ for ($i = 0; $i -lt 7; $i++) { $script:Ed.dayChecks[$i].Checked = ($i -ge 5) } })
    $dlg.Controls.AddRange(@($bAll, $bWk, $bWe))

    # Saatler
    D-Label 'Saatler' 15 196 120
    D-Label 'Başlangıç' 330 196 90 $FontN $Gray
    D-Label 'Bitiş' 430 196 90 $FontN $Gray
    $lstRanges = New-Object System.Windows.Forms.ListBox
    $lstRanges.Location = New-Object System.Drawing.Point(15, 218); $lstRanges.Size = New-Object System.Drawing.Size(300, 92)
    $lstRanges.Font = New-Object System.Drawing.Font('Consolas', 11)
    $dtStart = New-Object System.Windows.Forms.DateTimePicker
    $dtEnd = New-Object System.Windows.Forms.DateTimePicker
    foreach ($dt in @($dtStart, $dtEnd)) {
        $dt.Format = 'Custom'; $dt.CustomFormat = 'HH:mm'; $dt.ShowUpDown = $true
        $dt.Font = New-Object System.Drawing.Font('Segoe UI', 12)
        $dt.Size = New-Object System.Drawing.Size(90, 30)
    }
    $dtStart.Location = New-Object System.Drawing.Point(330, 218); $dtStart.Value = [datetime]::Today.AddHours(9)
    $dtEnd.Location = New-Object System.Drawing.Point(430, 218);   $dtEnd.Value = [datetime]::Today.AddHours(12)
    $btnAddR = New-Object System.Windows.Forms.Button; $btnAddR.Text = '+ Aralık ekle'; $btnAddR.Location = New-Object System.Drawing.Point(330, 252); $btnAddR.Size = New-Object System.Drawing.Size(190, 28)
    $btnDelR = New-Object System.Windows.Forms.Button; $btnDelR.Text = 'Seçili aralığı sil'; $btnDelR.Location = New-Object System.Drawing.Point(330, 284); $btnDelR.Size = New-Object System.Drawing.Size(190, 28)
    $dlg.Controls.AddRange(@($lstRanges, $dtStart, $dtEnd, $btnAddR, $btnDelR))
    D-Label 'Başlangıç = bitiş → tüm gün.  23:00 → 07:00 gibi aralıklar gece yarısını aşar.' 15 316 530 $FontN $Gray
    $script:Ed.lst = $lstRanges; $script:Ed.dtS = $dtStart; $script:Ed.dtE = $dtEnd

    $script:Ed.refresh = {
        $script:Ed.lst.Items.Clear()
        foreach ($g in $script:Ed.ranges) {
            $len = Get-RangeLen $g
            [void]$script:Ed.lst.Items.Add(("{0}   ({1})" -f (Format-Range $g), $(if ($g.s -eq $g.e) { '24 sa' } else { Format-Duration $len })))
        }
    }
    $btnAddR.Add_Click({
        $s = $script:Ed.dtS.Value.Hour * 60 + $script:Ed.dtS.Value.Minute
        $e = $script:Ed.dtE.Value.Hour * 60 + $script:Ed.dtE.Value.Minute
        [void]$script:Ed.ranges.Add((New-Range $s $e))
        & $script:Ed.refresh
    })
    $btnDelR.Add_Click({
        $i = $script:Ed.lst.SelectedIndex
        if ($i -ge 0) { $script:Ed.ranges.RemoveAt($i); & $script:Ed.refresh }
    })

    # Favoriler
    D-Label 'Favoriler (site + program birlikte)' 15 344 400
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(15, 366); $clb.Size = New-Object System.Drawing.Size(530, 104)
    $clb.MultiColumn = $true; $clb.ColumnWidth = 170; $clb.CheckOnClick = $true
    foreach ($p in $OK_Presets) { [void]$clb.Items.Add($p.name) }
    $dlg.Controls.Add($clb)

    # Diğer programlar
    D-Label 'Diğer programlar (her satıra bir ad, örn. steam)' 15 480 400
    $txtProcs = New-Object System.Windows.Forms.TextBox
    $txtProcs.Multiline = $true; $txtProcs.ScrollBars = 'Vertical'; $txtProcs.AcceptsReturn = $true
    $txtProcs.Location = New-Object System.Drawing.Point(15, 502); $txtProcs.Size = New-Object System.Drawing.Size(360, 64)
    $btnPick = New-Object System.Windows.Forms.Button; $btnPick.Text = 'Çalışanlardan seç...'; $btnPick.Location = New-Object System.Drawing.Point(385, 502); $btnPick.Size = New-Object System.Drawing.Size(160, 30)
    $dlg.Controls.AddRange(@($txtProcs, $btnPick))
    $script:Ed.txtProcs = $txtProcs; $script:Ed.dlg = $dlg

    $btnPick.Add_Click({
        $pd = New-Object System.Windows.Forms.Form
        $pd.Text = 'Çalışan programlar'; $pd.ClientSize = New-Object System.Drawing.Size(420, 420)
        $pd.StartPosition = 'CenterParent'; $pd.Font = $FontN
        $list = New-Object System.Windows.Forms.CheckedListBox
        $list.Location = New-Object System.Drawing.Point(10, 10); $list.Size = New-Object System.Drawing.Size(400, 350); $list.CheckOnClick = $true
        $procs = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.ProcessName -notin @('explorer', 'powershell', 'ApplicationFrameHost', 'TextInputHost', 'SystemSettings') } |
            Sort-Object ProcessName -Unique
        foreach ($p in $procs) {
            $title = [string]$p.MainWindowTitle
            if ($title.Length -gt 40) { $title = $title.Substring(0, 40) + '…' }
            [void]$list.Items.Add("$($p.ProcessName)    ($title)")
        }
        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = 'Ekle'; $ok.Location = New-Object System.Drawing.Point(310, 372); $ok.Size = New-Object System.Drawing.Size(100, 34); $ok.DialogResult = 'OK'
        $pd.Controls.AddRange(@($list, $ok)); $pd.AcceptButton = $ok
        if ($pd.ShowDialog($script:Ed.dlg) -eq 'OK') {
            $cur = @(($script:Ed.txtProcs.Text -split "\r?\n") | ForEach-Object { Get-ProcName $_ } | Where-Object { $_ })
            foreach ($item in $list.CheckedItems) {
                $name = Get-ProcName ((([string]$item) -split '\s{4}')[0])
                if ($cur -notcontains $name) { $cur += $name }
            }
            $script:Ed.txtProcs.Text = ($cur -join "`r`n")
        }
    })

    # Diğer siteler
    D-Label 'Diğer siteler (her satıra bir site, örn. 9gag.com)' 15 576 400
    $txtSites = New-Object System.Windows.Forms.TextBox
    $txtSites.Multiline = $true; $txtSites.ScrollBars = 'Vertical'; $txtSites.AcceptsReturn = $true
    $txtSites.Location = New-Object System.Drawing.Point(15, 598); $txtSites.Size = New-Object System.Drawing.Size(530, 52)
    $dlg.Controls.Add($txtSites)

    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = 'Kaydet'; $btnOk.Font = $FontB
    $btnOk.Location = New-Object System.Drawing.Point(335, 662); $btnOk.Size = New-Object System.Drawing.Size(100, 34)
    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = 'Vazgeç'
    $btnCancel.Location = New-Object System.Drawing.Point(445, 662); $btnCancel.Size = New-Object System.Drawing.Size(100, 34); $btnCancel.DialogResult = 'Cancel'
    $dlg.Controls.AddRange(@($btnOk, $btnCancel)); $dlg.CancelButton = $btnCancel

    # --- Mevcut değerleri doldur ---
    $presetProcs = @(); $presetSites = @()
    if ($null -ne $rule) {
        $txtName.Text = $rule.name
        if ($rule.kind -eq 'ders') { $rbDers.Checked = $true } else { $rbRutin.Checked = $true }
        for ($i = 0; $i -lt 7; $i++) { $dayChecks[$i].Checked = [bool]$rule.days[$i] }
        foreach ($g in @($rule.ranges)) { if ($null -ne $g) { [void]$script:Ed.ranges.Add((New-Range $g.s $g.e)) } }
        $apps = L $rule.apps; $sites = L $rule.sites
        for ($k = 0; $k -lt $OK_Presets.Count; $k++) {
            $p = $OK_Presets[$k]; $hit = $false
            foreach ($s in $p.sites) { if ($sites -contains $s) { $hit = $true } }
            foreach ($a in $p.procs) { if ($apps -contains $a) { $hit = $true } }
            if ($hit) {
                $clb.SetItemChecked($k, $true)
                $presetProcs += @($p.procs); $presetSites += @($p.sites)
            }
        }
        $txtProcs.Text = (@($apps | Where-Object { $presetProcs -notcontains $_ }) -join "`r`n")
        $txtSites.Text = (@($sites | Where-Object { $presetSites -notcontains $_ }) -join "`r`n")
    } else {
        $rbRutin.Checked = $true
        foreach ($c in $dayChecks) { $c.Checked = $true }
        [void]$script:Ed.ranges.Add((New-Range 540 720))
    }
    & $script:Ed.refresh

    $script:Ed.txtName = $txtName; $script:Ed.rbDers = $rbDers; $script:Ed.clb = $clb; $script:Ed.txtSites = $txtSites
    $script:Ed.ruleId = if ($null -ne $rule) { $rule.id } else { New-RuleId }

    $btnOk.Add_Click({
        $E = $script:Ed
        $kind = if ($E.rbDers.Checked) { 'ders' } else { 'rutin' }
        $name = $E.txtName.Text.Trim()
        if (-not $name) { $name = if ($kind -eq 'ders') { 'Ders' } else { 'Rutin' } }
        $days = [bool[]]@($E.dayChecks | ForEach-Object { $_.Checked })
        if ($kind -eq 'rutin' -and $E.ranges.Count -eq 0) { Show-Msg 'Rutin kural için en az bir saat aralığı ekle.' 'Warning'; return }
        if ($E.ranges.Count -gt 0 -and -not ($days -contains $true)) { Show-Msg 'En az bir gün seç.' 'Warning'; return }
        $apps = New-Object System.Collections.Generic.List[string]
        $sites = New-Object System.Collections.Generic.List[string]
        foreach ($idx in $E.clb.CheckedIndices) {
            $p = $OK_Presets[[int]$idx]
            foreach ($a in $p.procs) { if (-not $apps.Contains($a)) { $apps.Add($a) } }
            foreach ($s in $p.sites) { if (-not $sites.Contains($s)) { $sites.Add($s) } }
        }
        foreach ($line in ($E.txtProcs.Text -split "\r?\n")) { $a = Get-ProcName $line; if ($a -and -not $apps.Contains($a)) { $apps.Add($a) } }
        foreach ($line in ($E.txtSites.Text -split "\r?\n")) {
            $s = Get-NormalHost $line
            if ($s -and $s -notmatch '\s' -and $s.Contains('.') -and -not $sites.Contains($s)) { $sites.Add($s) }
        }
        if ($apps.Count -eq 0 -and $sites.Count -eq 0) { Show-Msg 'En az bir favori, program ya da site seç.' 'Warning'; return }
        $E.result = ConvertTo-Rule @{
            id = $E.ruleId; name = $name; kind = $kind; days = $days
            ranges = @($E.ranges | ForEach-Object { @{ s = $_.s; e = $_.e } })
            apps = $apps.ToArray(); sites = $sites.ToArray()
        }
        $E.dlg.DialogResult = 'OK'
        $E.dlg.Close()
    })

    [void]$dlg.ShowDialog($form)
    return $script:Ed.result
}

# =====================================================================
#  Ana pencere
# =====================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Odak Kilidi'
$form.ClientSize = New-Object System.Drawing.Size(720, 680)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = $FontN
$form.BackColor = [System.Drawing.Color]::White

function Add-Label($text, $x, $y, $w, $h, $font = $FontN, $color = $null) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = $font
    if ($color) { $l.ForeColor = $color }
    $form.Controls.Add($l)
    return $l
}
function Add-Button($text, $x, $y, $w, $h = 32) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $form.Controls.Add($b)
    return $b
}

$lblStatus = Add-Label '' 15 12 690 64 $FontH
$lblStatus.ForeColor = [System.Drawing.Color]::White
$lblStatus.TextAlign = 'MiddleCenter'

# Ders modu
$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = 'Ders modu'; $grp.Font = $FontB; $grp.ForeColor = $Navy
$grp.Location = New-Object System.Drawing.Point(15, 84); $grp.Size = New-Object System.Drawing.Size(690, 84)
$form.Controls.Add($grp)
$lblSession = New-Object System.Windows.Forms.Label
$lblSession.Font = $FontN; $lblSession.ForeColor = [System.Drawing.Color]::Black
$lblSession.Location = New-Object System.Drawing.Point(12, 24); $lblSession.Size = New-Object System.Drawing.Size(440, 50)
$cmbDur = New-Object System.Windows.Forms.ComboBox
$cmbDur.DropDownStyle = 'DropDownList'; $cmbDur.Font = $FontN
$cmbDur.Location = New-Object System.Drawing.Point(460, 32); $cmbDur.Size = New-Object System.Drawing.Size(95, 28)
foreach ($d in $DurLabels) { [void]$cmbDur.Items.Add($d) }
$cmbDur.SelectedIndex = 1
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Font = $FontB; $btnStart.BackColor = $Accent; $btnStart.ForeColor = [System.Drawing.Color]::White; $btnStart.FlatStyle = 'Flat'
$btnStart.Location = New-Object System.Drawing.Point(565, 29); $btnStart.Size = New-Object System.Drawing.Size(112, 34)
$grp.Controls.AddRange(@($lblSession, $cmbDur, $btnStart))

# Kurallar
[void](Add-Label 'Kurallar' 15 178 300 22 $FontH $Navy)
$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false; $lv.GridLines = $true
$lv.Location = New-Object System.Drawing.Point(15, 202); $lv.Size = New-Object System.Drawing.Size(690, 230)
[void]$lv.Columns.Add('Ad', 130)
[void]$lv.Columns.Add('Tür', 60)
[void]$lv.Columns.Add('Günler', 110)
[void]$lv.Columns.Add('Saatler', 170)
[void]$lv.Columns.Add('Hedefler', 215)
$form.Controls.Add($lv)

$btnNew  = Add-Button '+ Yeni kural' 15 440 130 34
$btnNew.Font = $FontB
$btnEdit = Add-Button 'Düzenle' 155 440 110 34
$btnDel  = Add-Button 'Sil' 275 440 90 34
[void](Add-Label 'Kısıtlamayı ARTIRAN değişiklik hemen, AZALTAN değişiklik (saat kısaltma, hedef çıkarma, kural silme) ertesi gün geçerli olur.' 375 438 330 40 $FontN $Gray)

$lblPending = Add-Label '' 15 488 520 36 $FontN $Amber
$btnCancelPending = Add-Button 'Bekleyeni iptal et' 545 486 160

[void](Add-Label 'Kaldırma' 15 534 300 22 $FontH $Navy)
$lblUnlock = Add-Label '' 15 558 520 70
$btnUnlock = Add-Button '' 545 558 160
$btnUninstall = Add-Button 'Şimdi kaldır' 545 596 160

# ---------------- Durum ----------------
function Update-Form {
    $st = Read-OKState
    if ($null -eq $st) { return }
    $script:St = $st
    $cfg = $st.active
    $wm = Get-WeekMinute
    $session = Test-SessionActive $st

    # Üst durum
    $activeRules = @(@($cfg.rules) | Where-Object { $null -ne $_ -and (Test-RuleCovers $_ $wm) })
    if (-not (Test-WorkerAlive)) {
        $lblStatus.Text = 'Arka plan servisi çalışmıyor! Kur.bat ile yeniden kur.'
        $lblStatus.BackColor = $Red
    } elseif ($activeRules.Count -gt 0 -or $session) {
        $parts = @()
        foreach ($r in $activeRules) {
            $f = Get-RuleFreeIn $r $wm
            $until = if ($f -lt 0) { 'sürekli' } else { "$(Format-WeekMinute (($wm + $f) % $OK_Week) $wm)'e kadar" }
            $parts += "$($r.name) ($until)"
        }
        if ($session) { $parts += "Ders modu ($((Get-SessionEnd $st).ToString('HH:mm'))'e kadar)" }
        $lblStatus.Text = "KİLİTLİ: " + ($parts -join ' · ')
        $lblStatus.BackColor = $Red
    } elseif (@($cfg.rules).Count -eq 0) {
        $lblStatus.Text = 'Henüz kural yok — "+ Yeni kural" ile ekle'
        $lblStatus.BackColor = $Amber
    } else {
        $best = -1; $bestName = ''
        foreach ($r in @($cfg.rules)) {
            $d = Get-RuleStartsIn $r $wm
            if ($d -ge 0 -and ($best -lt 0 -or $d -lt $best)) { $best = $d; $bestName = $r.name }
        }
        $lblStatus.Text = 'Şu an serbest' + $(if ($best -ge 0) { " — sıradaki: $bestName, $(Format-WeekMinute (($wm + $best) % $OK_Week) $wm)" } else { '' })
        $lblStatus.BackColor = $Green
    }

    # Ders modu
    $dt = Get-DersTargets $cfg
    if ($session) {
        $end = Get-SessionEnd $st
        $left = [int][math]::Ceiling(($end - (Get-Date)).TotalMinutes)
        $lblSession.Text = "Ders modu AÇIK — $($end.ToString('HH:mm'))'e kadar ($(Format-Duration $left)). Erken bitirilemez."
        $btnStart.Text = 'Uzat'
    } elseif ($dt.Count -eq 0) {
        $lblSession.Text = 'Önce "Ders" türünde bir kural ekle. "Ders başlat"a basınca o kuralların hedefleri seçtiğin süre boyunca kilitlenir.'
        $btnStart.Text = 'Ders başlat'
    } else {
        $names = @(@($cfg.rules) | Where-Object { $_.kind -eq 'ders' } | ForEach-Object { $_.name })
        $lblSession.Text = "Başlatınca kilitlenecek kurallar: $($names -join ', ')"
        $btnStart.Text = 'Ders başlat'
    }

    # Kural listesi (bekleyen varsa onu göster)
    $shown = if ($null -ne $st.pending) { $st.pending } else { $cfg }
    $script:Rules = @(@($shown.rules) | Where-Object { $null -ne $_ })
    $sel = if ($lv.SelectedIndices.Count -gt 0) { $lv.SelectedIndices[0] } else { -1 }
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($r in $script:Rules) {
        $on = (Test-RuleCovers $r $wm)
        $it = New-Object System.Windows.Forms.ListViewItem(([string]$r.name + $(if ($on) { '  (kilitli)' } else { '' })))
        [void]$it.SubItems.Add($(if ($r.kind -eq 'ders') { 'Ders' } else { 'Rutin' }))
        $rg = @(@($r.ranges) | Where-Object { $null -ne $_ })
        if ($rg.Count -eq 0) {
            [void]$it.SubItems.Add('-')
            [void]$it.SubItems.Add('Sadece butonla')
        } else {
            [void]$it.SubItems.Add((Format-Days $r.days))
            [void]$it.SubItems.Add((@($rg | ForEach-Object { Format-Range $_ }) -join ', '))
        }
        [void]$it.SubItems.Add((Get-TargetsText $r))
        if ($on) { $it.ForeColor = $Red }
        [void]$lv.Items.Add($it)
    }
    if ($sel -ge 0 -and $sel -lt $lv.Items.Count) { $lv.Items[$sel].Selected = $true }
    $lv.EndUpdate()

    # Bekleyen
    if ($st.pendingDate) {
        $lblPending.Text = "Bekleyen değişiklikler $($st.pendingDate) tarihinde geçerli olacak (liste o hâli gösteriyor)."
        $btnCancelPending.Visible = $true
    } else {
        $lblPending.Text = ''
        $btnCancelPending.Visible = $false
    }

    # Kaldırma
    $today = Get-Today
    $btnUninstall.Visible = $false
    if ($st.unlockDate -eq $today) {
        $lblUnlock.Text = 'Bugün kaldırma izni günü. "Şimdi kaldır" ile Odak Kilidi''ni silebilirsin.'
        $btnUnlock.Text = 'İzni iptal et'; $btnUnlock.Tag = 'cancelUnlock'
        $btnUninstall.Visible = $true
    } elseif ($st.unlockDate) {
        $lblUnlock.Text = "Kaldırma izni $($st.unlockDate) tarihinde, bir gün boyunca açılacak."
        $btnUnlock.Text = 'İzni iptal et'; $btnUnlock.Tag = 'cancelUnlock'
    } else {
        $lblUnlock.Text = 'Koruma açık: Odak Kilidi kaldırılamaz. Kaldırmak istersen izin iste; izin ertesi gün, bir gün boyunca açılır.'
        $btnUnlock.Text = 'Kaldırma izni iste'; $btnUnlock.Tag = 'unlock'
    }
}

# ---------------- Butonlar ----------------
$btnStart.Add_Click({
    if ((Get-DersTargets $script:St.active).Count -eq 0) {
        Show-Msg 'Önce "+ Yeni kural" ile türü "Ders" olan bir kural ekle ve kilitlenecek siteleri/programları seç. Saat girmek zorunda değilsin.'
        return
    }
    $i = [math]::Max(0, $cmbDur.SelectedIndex)
    if (-not (Ask-YesNo "$($DurLabels[$i]) ders modu başlatılsın mı?`r`nBaşladıktan sonra erken bitirilemez.")) { return }
    $res = Send-Request @{ type = 'startSession'; minutes = $DurMins[$i] }
    if ($res -ne 'OK') { Show-Msg 'Arka plan servisi yanıt vermedi.' 'Error' }
    Update-Form
})

$btnNew.Add_Click({
    $r = Show-RuleEditor $null
    if ($null -ne $r) { Save-Rules (@($script:Rules) + @($r)) }
})

$editAction = {
    if ($lv.SelectedIndices.Count -eq 0) { Show-Msg 'Önce listeden bir kural seç.'; return }
    $i = $lv.SelectedIndices[0]
    $r = Show-RuleEditor $script:Rules[$i]
    if ($null -ne $r) {
        $list = @($script:Rules)
        $list[$i] = $r
        Save-Rules $list
    }
}
$btnEdit.Add_Click($editAction)
$lv.Add_DoubleClick($editAction)

$btnDel.Add_Click({
    if ($lv.SelectedIndices.Count -eq 0) { Show-Msg 'Önce listeden bir kural seç.'; return }
    $i = $lv.SelectedIndices[0]
    if (-not (Ask-YesNo "`"$($script:Rules[$i].name)`" silinsin mi?`r`n(Silmek kısıtlamayı azalttığı için ertesi gün geçerli olur.)")) { return }
    $list = New-Object System.Collections.ArrayList
    for ($k = 0; $k -lt $script:Rules.Count; $k++) { if ($k -ne $i) { [void]$list.Add($script:Rules[$k]) } }
    Save-Rules $list
})

$btnCancelPending.Add_Click({
    [void](Send-Request @{ type = 'cancelPending' })
    Update-Form
})

$btnUnlock.Add_Click({
    if ($btnUnlock.Tag -eq 'unlock') {
        if (-not (Ask-YesNo "$(Get-Tomorrow) günü boyunca Odak Kilidi kaldırılabilir olacak. Emin misin?")) { return }
    }
    [void](Send-Request @{ type = [string]$btnUnlock.Tag })
    Update-Form
})

$btnUninstall.Add_Click({
    $u = Join-Path $PSScriptRoot 'uninstall.ps1'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $u)
    $form.Close()
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({ Update-Form })
$timer.Start()

Update-Form
[void]$form.ShowDialog()
$timer.Stop()
