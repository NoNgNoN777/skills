# ฟังก์ชันกลางของ agent-bridge (send / doctor ใช้ร่วมกัน)
# ค้นหาทุกอย่างใหม่ทุกครั้ง ไม่ฝังค่าตายตัว เพื่อให้ยังใช้ได้เมื่อแอปอัปเดตแล้วตำแหน่งหรือชื่อเปลี่ยน:
#   ตัวโปรแกรม = ExecutablePath ของ process ที่รันอยู่ · รหัส CSRF = จาก command line · port = ลองทุก port ที่ process เปิด
#   ชื่อตัวแปร = ให้ agentapi บอกเองว่าขาดตัวไหน · ชื่อคำสั่ง = อ่านจาก agentapi --help
# ถ้าค้นเองไม่เจอ ใส่ค่าเองได้ใน override.json (ดูตัวอย่างใน doctor.ps1) · config.json = ผลค้นล่าสุด (ลบทิ้งได้)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$AgbRoot  = $PSScriptRoot
$AgbInbox = Join-Path $AgbRoot 'to-claude'
$AgbZeroId = '00000000-0000-0000-0000-000000000000'

function Read-AgbJson([string]$name) {
    $p = Join-Path $AgbRoot $name
    if (Test-Path $p) { try { return (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { } }
    return $null
}

# ค่าที่ผู้ใช้กำหนดเอง (override.json) ชนะการค้นหาอัตโนมัติเสมอ
function Get-AgbOverride([string]$key) {
    $o = Read-AgbJson 'override.json'
    if ($o -and $o.PSObject.Properties[$key] -and $o.$key) { return $o.$key }
    return $null
}

function Save-AgbConfig([hashtable]$values) {
    $cur = [ordered]@{}
    $old = Read-AgbJson 'config.json'
    if ($old) { $old.PSObject.Properties | ForEach-Object { $cur[$_.Name] = $_.Value } }
    foreach ($k in $values.Keys) { $cur[$k] = $values[$k] }
    $cur['updated'] = (Get-Date).ToString('s')
    # ส่งหลายงานพร้อมกันอาจเขียนไฟล์ชนกัน ไฟล์นี้เป็นแค่ผลค้นล่าสุด เขียนไม่ได้ก็ไม่เป็นไร ห้ามทำให้การส่งล้ม
    try { [IO.File]::WriteAllText((Join-Path $AgbRoot 'config.json'), ($cur | ConvertTo-Json), (New-Object Text.UTF8Encoding $false)) } catch { }
}

# รุ่นที่ติดตั้ง (ตัวติดตั้งเขียนไว้ใน VERSION) · ใส่ในหัวข้อความ และเทียบกับ skill_version ที่ Gemini ตอบกลับ
function Get-AgbVersion {
    $p = Join-Path $AgbRoot 'VERSION'
    if (Test-Path -LiteralPath $p) { return ([IO.File]::ReadAllText($p)).Trim() }
    return '?'
}

# หาความลับในข้อความ คืนรายการ "บรรทัด N: ชนิด" ไม่คืนค่าที่เจอ (ห้ามพิมพ์ค่าออกไป)
$AgbSecretPatterns = [ordered]@{
    'private key'          = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'AWS access key'       = '\bAKIA[0-9A-Z]{16}\b'
    'GitHub token'         = '\bgh[pousr]_[A-Za-z0-9]{30,}'
    'Slack token'          = '\bxox[abposr]-[A-Za-z0-9-]{10,}'
    'Google API key'       = '\bAIza[0-9A-Za-z_-]{35}\b'
    'OpenAI/Anthropic key' = '\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}'
    'JWT'                  = '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    'webhook URL'          = '(?i)https://(?:discord(?:app)?\.com/api/webhooks|hooks\.slack\.com|[a-z0-9.-]*webhook[a-z0-9.-]*)/\S+'
    'connection string'    = '(?i)\b(?:password|pwd)\s*=\s*[^;\s]{4,}\s*;'
    'password/secret'      = '(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret)\b["'']?\s*[:=]\s*["'']?(?!(?:string|number|boolean|null|undefined|true|false|process\.|env\.|config\.|options\.|this\.|props\.|settings\.)\b|\(\?)[^\s"''<>{}$]{6,}'   # (? = regex ไม่ใช่ค่าจริง
    'Bearer token'         = '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{20,}'
}
function Find-AgbSecrets([string]$text) {
    $hits = @()
    $lines = $text -split '\r?\n'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($k in $AgbSecretPatterns.Keys) { if ($lines[$i] -match $AgbSecretPatterns[$k]) { $hits += "บรรทัด $($i + 1): $k" } }
    }
    return $hits
}

# ไฟล์ที่ห้ามส่ง path ให้ Gemini เปิดอ่าน (ชื่อบอกว่าเก็บความลับ)
$AgbBlockedFile = '(?i)(^\.env(\..*)?$|\.(pem|key|pfx|p12|jks|keystore|kdbx)$|^id_(rsa|dsa|ecdsa|ed25519)|credential|secret|\.npmrc$|\.pypirc$|\.netrc$)'

# บันทึกการส่งทุกครั้ง (sends.jsonl บรรทัดละ 1 งาน) ให้ pending.ps1 ใช้ดูงานค้าง · เขียนไม่ได้ก็ไม่ทำให้การส่งล้ม
function Add-AgbSendLog([Collections.IDictionary]$rec) {
    try {
        $line = ([pscustomobject]$rec | ConvertTo-Json -Compress -Depth 3) + "`n"
        [IO.File]::AppendAllText((Join-Path $AgbRoot 'sends.jsonl'), $line, (New-Object Text.UTF8Encoding $false))
    } catch { }
}

# root ของ repo ที่ใช้ตีความ path แบบ relative ในคำตอบ (apps/... ของ monorepo): โฟลเดอร์ที่มี .git ของไฟล์แนบ + root ที่ระบุเอง
function Get-AgbRepoRoots([string[]]$paths) {
    $roots = @()
    foreach ($p in $paths) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        $d = (Get-Item -LiteralPath $p).FullName
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { $d = Split-Path $d -Parent }
        $hit = $d
        for ($x = $d; $x; $x = Split-Path $x -Parent) { if (Test-Path -LiteralPath (Join-Path $x '.git')) { $hit = $x; break } }
        $roots += $hit
    }
    return @($roots | Select-Object -Unique)
}

# ตรวจโค้ดที่ Gemini ยกมาพร้อม path:line เทียบกับไฟล์จริง (Gemini เคยอ้างเนื้อหาไฟล์ที่ไม่มีอยู่จริงหลายรอบ)
# ต่อ 1 จุดอ้าง: หาไฟล์ (absolute หรือ relative ต่อ roots) แล้วเทียบบรรทัดในบล็อกโค้ดถัดไปกับไฟล์ช่วง ±20 บรรทัด
# คืนข้อความสรุปไว้พิมพ์หัวคำตอบ · ไม่มีจุดอ้างเลยคืนค่าว่าง
function Test-AgbQuotes([string]$reply, [string[]]$roots) {
    $norm = { param($s) ($s -replace '\s+', ' ').Trim() }
    $cite = '`(?<p>[^`\r\n]+?\.[A-Za-z0-9]{1,6}):(?<a>\d+)(?:[-–](?<b>\d+))?(?:,[\d\-–, ]+)?`|(?<p>(?:[A-Za-z]:[\\/])?[\w.@()\[\]-]+(?:[\\/][\w.@()\[\]-]+)+\.[A-Za-z0-9]{1,6}):(?<a>\d+)(?:[-–](?<b>\d+))?'
    $ms = [regex]::Matches($reply, $cite)
    if (-not $ms.Count) { return '' }
    $resolve = { param($rel) foreach ($cand in @($rel) + @($roots | ForEach-Object { Join-Path $_ ($rel -replace '/', '\') })) {
        if ($cand -and (Test-Path -LiteralPath $cand -PathType Leaf)) { return (Get-Item -LiteralPath $cand).FullName } } }
    # อ้างแค่ชื่อไฟล์หรือ path ท่อนท้าย (tab-feature.tsx:231, ui/tabs.tsx:32): จับคู่กับไฟล์ที่อ้างแบบ path เต็มไว้ในคำตอบนี้
    # ด้วยส่วนท้ายของ path · เจอได้มากกว่า 1 ไฟล์ (globals.css มีหลายที่) = กำกวม ไม่ตรวจ ดีกว่าเดาผิดไฟล์
    $known = @($ms | ForEach-Object { $r = $_.Groups['p'].Value.Trim(); if ($r -match '[\\/]') { & $resolve $r } } | Where-Object { $_ } | Select-Object -Unique)
    $bySuffix = { param($rel) $t = '\' + ($rel -replace '/', '\').TrimStart('\'); $c = @($known | Where-Object { $_.EndsWith($t, [StringComparison]::OrdinalIgnoreCase) }); if ($c.Count -eq 1) { $c[0] } }
    $ok = 0; $bad = @(); $nofile = @(); $skip = 0; $seen = @{}
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $m = $ms[$i]; $rel = $m.Groups['p'].Value.Trim(); $a = [int]$m.Groups['a'].Value
        $b = if ($m.Groups['b'].Success) { [int]$m.Groups['b'].Value } else { $a }
        $key = "$rel`:$a-$b"; if ($seen[$key]) { continue }; $seen[$key] = 1
        $file = if ($rel -match '[\\/]') { & $resolve $rel }; if (-not $file) { $file = & $bySuffix $rel }
        if (-not $file) { if ($rel -match '[\\/]' -and $rel -notmatch '^@') { $nofile += "$rel`:$a" } else { $skip++ }; continue }
        $lines = [IO.File]::ReadAllLines($file, [Text.Encoding]::UTF8)
        if ($a -gt $lines.Count) { $bad += "$rel`:$a — ไฟล์มีแค่ $($lines.Count) บรรทัด"; continue }
        # บล็อกโค้ดที่อยู่ถัดจากจุดอ้าง (ภายใน 400 ตัวอักษร และก่อนจุดอ้างถัดไป)
        $end = if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $reply.Length }
        $after = $reply.Substring($m.Index + $m.Length, [Math]::Min($end, $reply.Length) - ($m.Index + $m.Length))
        $blk = [regex]::Match($after, '(?s)^.{0,400}?```[^\r\n]*\r?\n(.*?)\r?\n\s*```')
        if (-not $blk.Success) { $ok++; continue }   # อ้างเลขบรรทัดอย่างเดียว: ผ่านถ้าบรรทัดมีจริง
        $code = @($blk.Groups[1].Value -split '\r?\n' | ForEach-Object { & $norm $_ } | Where-Object { $_.Length -ge 6 -and $_ -notmatch '^(\.\.\.|…|//\s*\.\.\.)' })
        if (-not $code.Count) { $ok++; continue }
        $lo = [Math]::Max(0, $a - 21); $hi = [Math]::Min($lines.Count - 1, $b + 19)
        $win = @($lines[$lo..$hi] | ForEach-Object { & $norm $_ })
        $hit = @($code | Where-Object { $c = $_; $win | Where-Object { $_.Contains($c) -or ($c.Length -gt 40 -and $_.Length -ge 20 -and $c.Contains($_)) } | Select-Object -First 1 }).Count
        if ($hit / $code.Count -ge 0.6) { $ok++ } else { $bad += "$rel`:$a — โค้ดที่ยกมาตรงไฟล์จริงแค่ $hit/$($code.Count) บรรทัด" }
    }
    $total = $ok + $bad.Count + $nofile.Count
    $out = "[ตรวจหลักฐาน: อ้าง $($total + $skip) จุด · ตรง $ok · ไม่ตรง $($bad.Count) · หาไฟล์ไม่เจอ $($nofile.Count) · ไม่ได้ตรวจ $skip (อ้างแค่ชื่อไฟล์หรือชื่อแพ็กเกจ)$(if ($bad.Count) { ' · ข้อที่อ้างไม่ตรงห้ามใช้จนกว่าจะเปิดไฟล์ดูเอง (ไฟล์ที่แก้หลังส่งงานไปจะขึ้นไม่ตรงได้)' })]"
    foreach ($x in ($bad | Select-Object -First 12)) { $out += "`n  - ไม่ตรง: $x" }
    foreach ($x in ($nofile | Select-Object -First 6)) { $out += "`n  - หาไฟล์ไม่เจอ: $x" }
    return $out
}

# ย้ายไฟล์คำตอบที่เก่ากว่า N วันไป to-claude\archive\<yyyyMM>\ (ย้าย ไม่ลบ) · ข้ามไฟล์ที่ยังรออยู่ (partial / need-user)
function Move-AgbOldReplies([int]$Days = 14) {
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $AgbInbox -Filter *.md -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -lt (Get-Date).AddDays(-$Days))) {
        try {
            $head = (Get-Content -LiteralPath $f.FullName -TotalCount 12 -Encoding UTF8) -join "`n"
            if ($head -match '(?m)^status:\s*["'']?(partial|need-user)\b') { continue }
            # เดือนจากชื่อไฟล์ (msg_id ขึ้นต้นด้วย yyyyMMdd) ไม่ใช้ LastWriteTime ที่อาจถูกแตะใหม่ · pending.ps1 หาไฟล์จากเดือนนี้
            $ym = if ($f.Name -match '^(\d{6})\d{2}-') { $Matches[1] } else { $f.LastWriteTime.ToString('yyyyMM') }
            $to = Join-Path $AgbInbox "archive\$ym"
            New-Item -ItemType Directory -Force $to | Out-Null
            Move-Item -LiteralPath $f.FullName (Join-Path $to $f.Name) -Force; $n++
        } catch { }
    }
    return $n
}

# process ของ language server ที่ Antigravity เปิดไว้ + รหัส CSRF (ไม่พิมพ์ ไม่บันทึก)
function Find-AgbServer {
    $like  = Get-AgbOverride 'process_name_like'; if (-not $like) { $like = 'language_server*' }
    $procs = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -like $like -and $_.CommandLine -match '(?i)antigravity' })
    if (-not $procs) { throw "ไม่พบ Antigravity ที่เปิดอยู่ (ไม่มี process ชื่อ $like ที่เกี่ยวกับ antigravity) · เปิดแอปก่อน ถ้าเปิดอยู่แล้วให้รัน doctor.ps1" }
    $hint = Get-AgbOverride 'process_hint'; if (-not $hint) { $hint = 'subclient_type hub' }
    $p = $procs | Where-Object { $_.CommandLine -match [regex]::Escape($hint) } | Select-Object -First 1
    if (-not $p) { $p = $procs | Where-Object { $_.CommandLine -match '(?i)csrf' } | Select-Object -First 1 }
    if (-not $p) { throw 'เจอ process ของ Antigravity แต่ไม่มีตัวไหนมีรหัส CSRF · รัน doctor.ps1' }
    $csrf = $null
    if ($p.CommandLine -match '--csrf_token[= ](\S+)') { $csrf = $Matches[1].Trim('"', "'") }
    elseif ($p.CommandLine -match '(?i)--[\w-]*csrf[\w-]*[= ](\S+)') { $csrf = $Matches[1].Trim('"', "'") }
    if (-not $csrf) { throw 'อ่านรหัส CSRF จาก process ไม่ได้ (รูปแบบ command line อาจเปลี่ยน) · รัน doctor.ps1' }
    $ver = '?'
    if ($p.CommandLine -match '--override_ide_version[= ](\S+)') { $ver = $Matches[1] }
    $exe = Get-AgbOverride 'exe'; if (-not $exe) { $exe = $p.ExecutablePath }
    [pscustomobject]@{ Exe = $exe; ProcId = $p.ProcessId; Csrf = $csrf; Version = $ver; CommandLine = $p.CommandLine }
}

# ไม่ใช้ & $exe @args เพราะ Windows PowerShell 5.1 ส่ง argument ที่มี " ผิด (" หาย, \ ท้ายข้อความกลืนเครื่องหมายปิด,
# ข้อความถูกแยกเป็นหลาย argument) จึงสร้าง command line เองตามกฎของ Windows (CommandLineToArgvW) แล้วเรียก Process.Start ตรงๆ
function ConvertTo-AgbQuotedArg([string]$a) {
    $s = [regex]::Replace($a, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
    $s = [regex]::Replace($s, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
    return '"' + $s + '"'
}

function Invoke-Agb([string]$exe, [string[]]$argv) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = ($argv | ForEach-Object { ConvertTo-AgbQuotedArg $_ }) -join ' '
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()   # อ่านสองท่อพร้อมกัน กันค้างเมื่อ output ยาว
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return (($out, $errTask.Result) | Where-Object { $_ }) -join "`n"
}

# ชื่อคำสั่งย่อยของ agentapi อ่านจาก --help ถ้าชื่อเดิมหายไปจะลองหาชื่อที่ใกล้เคียง
function Get-AgbHelp([string]$exe) { Invoke-Agb $exe @('agentapi', '--help') }

function Resolve-AgbCommands([string]$exe) {
    $help = Get-AgbHelp $exe
    $cmds = @([regex]::Matches($help, '(?m)^\s+([a-z][a-z0-9-]+)\b') | ForEach-Object { $_.Groups[1].Value })
    $want = [ordered]@{
        meta = @('get-conversation-metadata', 'metadata|get-conv')
        send = @('send-message', 'send|message')
        new  = @('new-conversation', 'new|create')
    }
    $res = [ordered]@{}
    foreach ($k in $want.Keys) {
        $o = Get-AgbOverride "cmd_$k"
        if ($o) { $res[$k] = $o; continue }
        $def, $pat = $want[$k]
        if ($cmds -contains $def) { $res[$k] = $def; continue }
        $alt = $cmds | Where-Object { $_ -match $pat } | Select-Object -First 1
        if ($alt) { $res[$k] = $alt; continue }
        throw "ไม่พบคำสั่ง agentapi สำหรับ '$k' (เดิมชื่อ $def) · คำสั่งที่มีตอนนี้: $($cmds -join ', ') · ใส่ชื่อใหม่ใน override.json ช่อง cmd_$k"
    }
    $models = @()
    # ตัด model_id ออก: help เขียน <flash_lite|flash|pro|model_id> โดย model_id แปลว่า "ใส่ id อื่นได้" ไม่ใช่ชื่อโมเดล
    if ($help -match '--model=<([^>]+)>') { $models = @($Matches[1] -split '\|' | Where-Object { $_ -and $_ -ne 'model_id' }) }
    [pscustomobject]@{ Meta = $res.meta; Send = $res.send; New = $res.new; Models = $models; Help = $help; All = $cmds }
}

# ชื่อตัวแปรที่ agentapi ใช้หา server: ให้มันบอกเองจาก error "<NAME> is not set"
function Resolve-AgbEnvNames([string]$exe, [string]$metaCmd) {
    $addr = Get-AgbOverride 'env_address'; $csrf = Get-AgbOverride 'env_csrf'
    if (-not $addr) {
        $addr = 'ANTIGRAVITY_LS_ADDRESS'
        Remove-Item "env:$addr" -ErrorAction SilentlyContinue
        $out = Invoke-Agb $exe @('agentapi', $metaCmd, $AgbZeroId)
        if ($out -match '\b([A-Z][A-Z0-9_]*ADDRESS[A-Z0-9_]*) is not set') { $addr = $Matches[1] }
    }
    if (-not $csrf) { $csrf = ($addr -replace 'LS_ADDRESS$', '') + 'CSRF_TOKEN' }
    @($addr, $csrf)
}

# โปรเจกต์ของ Antigravity (เปิดแชทใหม่ต้องระบุ) อยู่ใน ~/.gemini/*/projects/*.json มี id กับ name
function Get-AgbProjects {
    $dirs = @(Get-ChildItem "$HOME\.gemini" -Directory -ErrorAction SilentlyContinue |
              ForEach-Object { Join-Path $_.FullName 'projects' } | Where-Object { Test-Path $_ })
    foreach ($d in $dirs) {
        foreach ($f in Get-ChildItem $d -Filter *.json) {
            try { $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
            if (-not $j.id) { continue }
            $folders = @($j.projectResources.resources | ForEach-Object { [uri]::UnescapeDataString("$($_.folderUri)") -replace '^file:///', '' })
            [pscustomobject]@{ Id = $j.id; Name = [uri]::UnescapeDataString("$($j.name)"); Folders = $folders; Modified = $f.LastWriteTime }
        }
    }
}

function Find-AgbProject([string]$key) {
    $all = @(Get-AgbProjects)
    $hit = @($all | Where-Object { $_.Id -eq $key -or $_.Id.StartsWith($key) })
    if (-not $hit) { $hit = @($all | Where-Object { $_.Name -eq $key }) }
    # path ใน folderUri ใช้ / แต่ Windows มักพิมพ์ \ จึงแปลงให้เหมือนกันก่อนเทียบ
    $k = [regex]::Escape(($key -replace '\\', '/').TrimEnd('/'))
    if (-not $hit) { $hit = @($all | Where-Object { ($_.Folders -replace '\\', '/') -match "(?i)$k" }) }
    if ($hit.Count -eq 1) { return $hit[0] }
    if ($hit.Count -gt 1) {
        # ชื่อซ้ำ: เลือกตัวที่แก้ล่าสุด แต่บอกด้วย
        $pick = $hit | Sort-Object Modified -Descending | Select-Object -First 1
        Write-Warning "โปรเจกต์ชื่อ '$key' มี $($hit.Count) ตัว เลือกตัวที่แก้ล่าสุด ($($pick.Id))"
        return $pick
    }
    throw "ไม่พบโปรเจกต์ '$key' · ที่มี: $(($all | ForEach-Object { $_.Name }) -join ', ')"
}

# หา port ที่ใช้งานได้ ลอง port ที่จำไว้ก่อน แล้วไล่ทุก port ที่ process เปิด
function Connect-Agb([string]$probeId) {
    if (-not $probeId) { $probeId = $AgbZeroId }
    $srv  = Find-AgbServer
    $cmds = Resolve-AgbCommands $srv.Exe
    $envs = Resolve-AgbEnvNames $srv.Exe $cmds.Meta
    Set-Item "env:$($envs[1])" $srv.Csrf
    $ports = @(Get-NetTCPConnection -State Listen -OwningProcess $srv.ProcId -ErrorAction SilentlyContinue |
               Select-Object -ExpandProperty LocalPort -Unique)
    $cfg = Read-AgbJson 'config.json'
    if ($cfg -and $cfg.port -and ($ports -contains [int]$cfg.port)) { $ports = @([int]$cfg.port) + @($ports | Where-Object { $_ -ne [int]$cfg.port }) }
    $authFail = $false; $found = $null
    foreach ($p in $ports) {
        Set-Item "env:$($envs[0])" "127.0.0.1:$p"
        $out = Invoke-Agb $srv.Exe @('agentapi', $cmds.Meta, $probeId)
        if ($out -match '(?i)missing CSRF|unauthenticated') { $authFail = $true; continue }
        if ($out -match '(?i)Unavailable|connection error|is not set|forcibly closed') { continue }
        $found = $p; break
    }
    if (-not $found) {
        if ($authFail) { throw "เจอ server แต่รหัสไม่ผ่าน (ตัวแปร $($envs[1]) อาจเปลี่ยนชื่อ) · รัน doctor.ps1" }
        throw "เชื่อมต่อ language server ไม่ได้ (port ที่ลอง: $($ports -join ', ')) · รัน doctor.ps1"
    }
    Save-AgbConfig @{ port = $found; env_address = $envs[0]; env_csrf = $envs[1]; exe = $srv.Exe; app_version = $srv.Version
                      cmd_meta = $cmds.Meta; cmd_send = $cmds.Send; cmd_new = $cmds.New; models = ($cmds.Models -join '|') }
    [pscustomobject]@{ Exe = $srv.Exe; Port = $found; Cmd = $cmds; Version = $srv.Version }
}
