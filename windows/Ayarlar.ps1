# Odak Kilidi - ayar penceresi (yönetici gerekmez)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'common.ps1')

# ---------- Koyu tema renkleri ----------
$Bg       = [System.Drawing.Color]::FromArgb(14, 19, 34)
$Surface  = [System.Drawing.Color]::FromArgb(24, 32, 54)
$Surface2 = [System.Drawing.Color]::FromArgb(33, 43, 70)
$Border   = [System.Drawing.Color]::FromArgb(45, 56, 88)
$Text     = [System.Drawing.Color]::FromArgb(238, 241, 248)
$Navy     = $Text   # başlık yazıları
$Gray     = [System.Drawing.Color]::FromArgb(151, 161, 188)
$Accent   = [System.Drawing.Color]::FromArgb(124, 92, 255)
$Red      = [System.Drawing.Color]::FromArgb(229, 72, 77)
$Green    = [System.Drawing.Color]::FromArgb(31, 169, 113)
$Amber    = [System.Drawing.Color]::FromArgb(224, 154, 26)

# Koyu başlık çubuğu (Windows 10/11)
try {
    Add-Type -Namespace OK -Name Dwm -MemberDefinition '[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr h, int a, ref int v, int s);' -ErrorAction Stop
    $script:DarkTitle = $true
} catch { $script:DarkTitle = $false }

# Bir pencereyi ve içindeki her şeyi koyu temaya boyar
function Set-Theme($ctl) {
    if ($ctl -is [System.Windows.Forms.Form]) {
        $ctl.BackColor = $Bg; $ctl.ForeColor = $Text
        if ($script:DarkTitle) {
            $ctl.Add_HandleCreated({ try { $v = 1; [void][OK.Dwm]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) } catch {} })
        }
    }
    foreach ($c in $ctl.Controls) {
        switch ($c.GetType().Name) {
            'Button' {
                $c.FlatStyle = 'Flat'
                $c.FlatAppearance.BorderSize = 1
                $c.Cursor = [System.Windows.Forms.Cursors]::Hand
                if ($c.AccessibleName -eq 'primary') {
                    $c.BackColor = $Accent; $c.ForeColor = [System.Drawing.Color]::White; $c.FlatAppearance.BorderColor = $Accent
                    $c.Font = $FontB
                } else {
                    $c.BackColor = $Surface2; $c.ForeColor = $Text; $c.FlatAppearance.BorderColor = $Border
                }
            }
            { $_ -in @('TextBox', 'ListBox', 'CheckedListBox', 'NumericUpDown', 'ComboBox', 'ListView') } {
                $c.BackColor = $Surface; $c.ForeColor = $Text
                if ($c.GetType().Name -ne 'ComboBox') { $c.BorderStyle = 'FixedSingle' }
            }
            { $_ -in @('CheckBox', 'RadioButton') } { $c.ForeColor = $Text; $c.BackColor = [System.Drawing.Color]::Transparent }
            'GroupBox' { $c.ForeColor = $Text; $c.BackColor = $Bg }
        }
        if ($c.Controls.Count -gt 0) { Set-Theme $c }
    }
}
$FontN = New-Object System.Drawing.Font('Segoe UI', 10)
$FontB = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$FontH = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)

$QuickLabels = @('25 dk', '45 dk', '1 sa', '2 sa', '3 sa', '4 sa')
$QuickMins   = @(25, 45, 60, 120, 180, 240)

# Tarih -> "15:00", "Yarın 15:00" ya da "Sal 15:00"
function Format-Time([datetime]$t) {
    $hm = $t.ToString('HH:mm')
    if ($t.Date -eq (Get-Date).Date) { return $hm }
    if ($t.Date -eq (Get-Date).Date.AddDays(1)) { return "Yarın $hm" }
    return ("{0} {1}" -f $OK_DayNames[([int]$t.DayOfWeek + 6) % 7], $hm)
}

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
    $dlg.BackColor = $Bg

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
    $rbDers.Text = 'Ders (haftalık sabit ders saatleri)'; $rbDers.Location = New-Object System.Drawing.Point(250, 70); $rbDers.Size = New-Object System.Drawing.Size(300, 24)
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
        $ok.AccessibleName = 'primary'; Set-Theme $pd
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

    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = 'Kaydet'; $btnOk.Font = $FontB; $btnOk.AccessibleName = 'primary'
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
        if ($E.ranges.Count -eq 0) { Show-Msg 'En az bir saat aralığı ekle. (Anlık ders için ana penceredeki "Ders başlat" butonunu kullan.)' 'Warning'; return }
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

    Set-Theme $dlg
    [void]$dlg.ShowDialog($form)
    return $script:Ed.result
}

# =====================================================================
#  Ders çalışma penceresi: süre + başlangıç + neler kilitlensin
# =====================================================================
function Show-StudyDialog {
    $script:Sd = @{ result = $null }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Ders çalışmaya başla'
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 640)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.Font = $FontN
    $dlg.BackColor = $Bg
    $script:Sd.dlg = $dlg

    function S-Label($text, $x, $y, $w, $font = $FontB, $color = $Navy) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y)
        $l.Size = New-Object System.Drawing.Size($w, 22); $l.Font = $font; $l.ForeColor = $color
        $dlg.Controls.Add($l)
    }

    # Süre
    S-Label 'Ne kadar çalışacaksın?' 15 12 400
    $numH = New-Object System.Windows.Forms.NumericUpDown
    $numH.Minimum = 0; $numH.Maximum = 12; $numH.Value = 2
    $numH.Font = New-Object System.Drawing.Font('Segoe UI', 14)
    $numH.Location = New-Object System.Drawing.Point(15, 38); $numH.Size = New-Object System.Drawing.Size(70, 34)
    S-Label 'saat' 90 46 50 $FontN $Gray
    $numM = New-Object System.Windows.Forms.NumericUpDown
    $numM.Minimum = 0; $numM.Maximum = 55; $numM.Increment = 5; $numM.Value = 0
    $numM.Font = New-Object System.Drawing.Font('Segoe UI', 14)
    $numM.Location = New-Object System.Drawing.Point(145, 38); $numM.Size = New-Object System.Drawing.Size(70, 34)
    S-Label 'dakika' 220 46 60 $FontN $Gray
    $dlg.Controls.AddRange(@($numH, $numM))
    $script:Sd.numH = $numH; $script:Sd.numM = $numM
    for ($i = 0; $i -lt $QuickLabels.Count; $i++) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $QuickLabels[$i]; $b.Tag = $QuickMins[$i]
        $b.Location = New-Object System.Drawing.Point((15 + $i * 88), 80); $b.Size = New-Object System.Drawing.Size(82, 28)
        $b.Add_Click({
            $m = [int]$this.Tag
            $script:Sd.numH.Value = [math]::Floor($m / 60)
            $script:Sd.numM.Value = $m % 60
        })
        $dlg.Controls.Add($b)
    }

    # Başlangıç
    S-Label 'Ne zaman başlasın?' 15 122 400
    $rbNow = New-Object System.Windows.Forms.RadioButton
    $rbNow.Text = 'Şimdi'; $rbNow.Checked = $true
    $rbNow.Location = New-Object System.Drawing.Point(15, 148); $rbNow.Size = New-Object System.Drawing.Size(90, 26)
    $rbAt = New-Object System.Windows.Forms.RadioButton
    $rbAt.Text = 'Şu saatte:'
    $rbAt.Location = New-Object System.Drawing.Point(115, 148); $rbAt.Size = New-Object System.Drawing.Size(100, 26)
    $dtAt = New-Object System.Windows.Forms.DateTimePicker
    $dtAt.Format = 'Custom'; $dtAt.CustomFormat = 'HH:mm'; $dtAt.ShowUpDown = $true
    $dtAt.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $dtAt.Location = New-Object System.Drawing.Point(218, 146); $dtAt.Size = New-Object System.Drawing.Size(90, 30)
    $n = Get-Date
    $dtAt.Value = $n.Date.AddHours($n.Hour + 1)
    $dlg.Controls.AddRange(@($rbNow, $rbAt, $dtAt))
    $script:Sd.rbNow = $rbNow; $script:Sd.rbAt = $rbAt; $script:Sd.dtAt = $dtAt
    $dtAt.Add_ValueChanged({ $script:Sd.rbAt.Checked = $true })

    # Neler kilitlensin? (son seçim hazır gelir)
    $last = $script:St.lastSession
    if ($null -ne $last) { $iApps = L $last.apps; $iSites = L $last.sites }
    else { $iApps = [string[]]@('instagram'); $iSites = [string[]]@('instagram.com', 'youtube.com', 'youtu.be') }
    S-Label 'Neler kilitlensin?' 15 190 400
    S-Label $(if ($null -ne $last) { 'Son ders oturumundaki seçimin hazır geldi.' } else { 'İstediklerini işaretle.' }) 15 212 530 $FontN $Gray
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(15, 236); $clb.Size = New-Object System.Drawing.Size(530, 104)
    $clb.MultiColumn = $true; $clb.ColumnWidth = 170; $clb.CheckOnClick = $true
    $pProcs = @(); $pSites = @()
    for ($k = 0; $k -lt $OK_Presets.Count; $k++) {
        $p = $OK_Presets[$k]
        [void]$clb.Items.Add($p.name)
        $hit = $false
        foreach ($x in $p.sites) { if ($iSites -contains $x) { $hit = $true } }
        foreach ($x in $p.procs) { if ($iApps -contains $x) { $hit = $true } }
        if ($hit) { $clb.SetItemChecked($k, $true); $pProcs += @($p.procs); $pSites += @($p.sites) }
    }
    $dlg.Controls.Add($clb)

    S-Label 'Diğer programlar (her satıra bir ad)' 15 350 400
    $txtProcs = New-Object System.Windows.Forms.TextBox
    $txtProcs.Multiline = $true; $txtProcs.ScrollBars = 'Vertical'; $txtProcs.AcceptsReturn = $true
    $txtProcs.Location = New-Object System.Drawing.Point(15, 374); $txtProcs.Size = New-Object System.Drawing.Size(530, 52)
    $txtProcs.Text = (@($iApps | Where-Object { $pProcs -notcontains $_ }) -join "`r`n")
    S-Label 'Diğer siteler (her satıra bir site)' 15 436 400
    $txtSites = New-Object System.Windows.Forms.TextBox
    $txtSites.Multiline = $true; $txtSites.ScrollBars = 'Vertical'; $txtSites.AcceptsReturn = $true
    $txtSites.Location = New-Object System.Drawing.Point(15, 460); $txtSites.Size = New-Object System.Drawing.Size(530, 52)
    $txtSites.Text = (@($iSites | Where-Object { $pSites -notcontains $_ }) -join "`r`n")
    $dlg.Controls.AddRange(@($txtProcs, $txtSites))

    # Özet
    $lblSum = New-Object System.Windows.Forms.Label
    $lblSum.Location = New-Object System.Drawing.Point(15, 524); $lblSum.Size = New-Object System.Drawing.Size(530, 40)
    $lblSum.Font = $FontH; $lblSum.ForeColor = [System.Drawing.Color]::White; $lblSum.BackColor = $Accent; $lblSum.TextAlign = 'MiddleCenter'
    $dlg.Controls.Add($lblSum)
    $script:Sd.lblSum = $lblSum; $script:Sd.clb = $clb; $script:Sd.txtProcs = $txtProcs; $script:Sd.txtSites = $txtSites

    $script:Sd.calc = {
        $mins = [int]$script:Sd.numH.Value * 60 + [int]$script:Sd.numM.Value
        $now = Get-Date
        if ($script:Sd.rbNow.Checked) { $start = $now }
        else {
            $v = $script:Sd.dtAt.Value
            $start = $now.Date.AddHours($v.Hour).AddMinutes($v.Minute)
            if ($start -le $now) { $start = $start.AddDays(1) }
        }
        @{ mins = $mins; start = $start; end = $start.AddMinutes($mins) }
    }
    $script:Sd.update = {
        $c = & $script:Sd.calc
        if ($c.mins -le 0) { $script:Sd.lblSum.Text = 'Süre seç'; return }
        $from = if ($script:Sd.rbNow.Checked) { 'Şimdi' } else { Format-Time $c.start }
        $script:Sd.lblSum.Text = "$from  →  $(Format-Time $c.end)   ($(Format-Duration $c.mins))"
    }
    $numH.Add_ValueChanged({ & $script:Sd.update })
    $numM.Add_ValueChanged({ & $script:Sd.update })
    $rbNow.Add_CheckedChanged({ & $script:Sd.update })
    $dtAt.Add_ValueChanged({ & $script:Sd.update })

    $btnGo = New-Object System.Windows.Forms.Button
    $btnGo.Text = 'Başlat'; $btnGo.AccessibleName = 'primary'
    $btnGo.Location = New-Object System.Drawing.Point(335, 584); $btnGo.Size = New-Object System.Drawing.Size(100, 36)
    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = 'Vazgeç'; $btnNo.DialogResult = 'Cancel'
    $btnNo.Location = New-Object System.Drawing.Point(445, 584); $btnNo.Size = New-Object System.Drawing.Size(100, 36)
    $dlg.Controls.AddRange(@($btnGo, $btnNo)); $dlg.CancelButton = $btnNo
    S-Label 'Başladıktan sonra erken bitirilemez.' 15 592 300 $FontN $Gray

    $btnGo.Add_Click({
        $D = $script:Sd
        $c = & $D.calc
        if ($c.mins -lt 5) { Show-Msg 'Süre en az 5 dakika olmalı.' 'Warning'; return }
        $apps = New-Object System.Collections.Generic.List[string]
        $sites = New-Object System.Collections.Generic.List[string]
        foreach ($idx in $D.clb.CheckedIndices) {
            $p = $OK_Presets[[int]$idx]
            foreach ($a in $p.procs) { if (-not $apps.Contains($a)) { $apps.Add($a) } }
            foreach ($x in $p.sites) { if (-not $sites.Contains($x)) { $sites.Add($x) } }
        }
        foreach ($line in ($D.txtProcs.Text -split "\r?\n")) { $a = Get-ProcName $line; if ($a -and -not $apps.Contains($a)) { $apps.Add($a) } }
        foreach ($line in ($D.txtSites.Text -split "\r?\n")) {
            $x = Get-NormalHost $line
            if ($x -and $x -notmatch '\s' -and $x.Contains('.') -and -not $sites.Contains($x)) { $sites.Add($x) }
        }
        if ($apps.Count -eq 0 -and $sites.Count -eq 0) { Show-Msg 'Kilitlenecek en az bir şey seç.' 'Warning'; return }
        $from = if ($D.rbNow.Checked) { 'şimdi' } else { Format-Time $c.start }
        if (-not (Ask-YesNo "$(Format-Duration $c.mins) boyunca ($from → $(Format-Time $c.end)) seçtiklerin kilitli olacak.`r`n`r`nErken bitirilemez, iptal edilemez. Başlatılsın mı?")) { return }
        $D.result = @{
            type = 'startSession'
            start = $(if ($D.rbNow.Checked) { $null } else { $c.start.ToString('o', $OK_Inv) })
            minutes = $c.mins
            apps = $apps.ToArray(); sites = $sites.ToArray()
        }
        $D.dlg.DialogResult = 'OK'
        $D.dlg.Close()
    })

    & $script:Sd.update
    Set-Theme $dlg
    [void]$dlg.ShowDialog($form)
    return $script:Sd.result
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
$form.BackColor = $Bg

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
$lblSession.Font = $FontN; $lblSession.ForeColor = $Text
$lblSession.Location = New-Object System.Drawing.Point(12, 22); $lblSession.Size = New-Object System.Drawing.Size(520, 56)
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.AccessibleName = 'primary'
$btnStart.Text = 'Ders başlat...'
$btnStart.Location = New-Object System.Drawing.Point(540, 28); $btnStart.Size = New-Object System.Drawing.Size(138, 40)
$grp.Controls.AddRange(@($lblSession, $btnStart))

# Kurallar
[void](Add-Label 'Kurallar' 15 178 300 22 $FontH $Navy)
$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false; $lv.GridLines = $false
$lv.Location = New-Object System.Drawing.Point(15, 202); $lv.Size = New-Object System.Drawing.Size(690, 230)
[void]$lv.Columns.Add('Ad', 130)
[void]$lv.Columns.Add('Tür', 60)
[void]$lv.Columns.Add('Günler', 110)
[void]$lv.Columns.Add('Saatler', 170)
[void]$lv.Columns.Add('Hedefler', 215)
$form.Controls.Add($lv)

$btnNew  = Add-Button '+ Yeni kural' 15 440 130 34
$btnNew.AccessibleName = 'primary'
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
    $live = Get-ActiveSessions $st
    $alive = Get-AliveSessions $st
    $session = $live.Count -gt 0

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
        foreach ($x in $live) { $parts += "Ders ($(Format-Time (ConvertFrom-IsoTime $x.end))'e kadar)" }
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
    if ($alive.Count -eq 0) {
        $lblSession.Text = 'Ders çalışacağın zaman bas: süreyi, başlangıç saatini ve neyin kilitleneceğini seçersin. Başladıktan sonra erken bitirilemez.'
    } else {
        $lines = foreach ($x in $alive) {
            $s0 = ConvertFrom-IsoTime $x.start; $e0 = ConvertFrom-IsoTime $x.end
            $what = Get-TargetsText $x
            if ($s0 -le (Get-Date)) { "SÜRÜYOR: $(Format-Time $e0)'e kadar — $what" }
            else { "Planlandı: $(Format-Time $s0) → $(Format-Time $e0) — $what" }
        }
        $lblSession.Text = (@($lines) -join "`r`n")
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
            [void]$it.SubItems.Add('Saat yok')
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
    $req = Show-StudyDialog
    if ($null -eq $req) { return }
    $res = Send-Request $req
    switch ($res) {
        'OK'       { Show-Msg 'Ders oturumu başladı. Başarılar!' }
        'GECERSIZ' { Show-Msg 'Ders oturumu başlatılamadı (süre ya da saat geçersiz).' 'Warning' }
        default    { Show-Msg 'Arka plan servisi yanıt vermedi.' 'Error' }
    }
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

Set-Theme $form
Update-Form
[void]$form.ShowDialog()
$timer.Stop()
