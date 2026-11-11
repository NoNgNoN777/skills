# ฟังก์ชันกลางของฝั่ง Codex และ Claude Code (หา exe, รายชื่อแชท Codex, ไฟล์ประวัติ, เรียกโปรแกรมภายนอก) · ai-bridge
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }

# เรียกโปรแกรมภายนอกแล้วคืน @{ Out = <บรรทัด stdout+stderr>; Code = <exit code> }
# PS 5.1 ที่ ErrorActionPreference=Stop จะ throw ทันทีเมื่อโปรแกรมพิมพ์อะไรลง stderr (แม้เป็นแค่คำเตือน)
# ทั้งที่งานสำเร็จแล้ว จึงลดเป็น Continue เฉพาะตอนเรียก แล้วตัดสินจาก exit code อย่างเดียว
function Invoke-Native([string]$exe, [string[]]$argv, [string]$stdin) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($PSBoundParameters.ContainsKey('stdin')) { $out = $stdin | & $exe @argv 2>&1 | ForEach-Object { "$_" } }
        else { $out = & $exe @argv 2>&1 | ForEach-Object { "$_" } }
        return @{ Out = @($out); Code = $LASTEXITCODE }
    } finally { $ErrorActionPreference = $prev }
}

function Find-Codex {
    $cmd = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $pkg = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) {
        $exe = Join-Path $pkg.InstallLocation 'app\resources\codex.exe'
        if (Test-Path $exe) { return $exe }
    }
    throw 'ไม่พบ codex.exe (ติดตั้งแอป Codex หรือ Codex CLI ก่อน)'
}

function Get-ClaudeVersion([string]$exe) {
    try { $v = ((Invoke-Native $exe @('--version')).Out | Select-Object -First 1) -as [string] } catch { $v = '' }
    if ($v -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return [version]'0.0.0'
}

function Find-Claude {
    # รุ่นใหม่สุดชนะ: claude.exe รุ่นเก่าใน PATH อาจไม่มีเครื่องมือ ListAgents/SendMessage
    $cands = @()
    $cmd = Get-Command claude.exe -All -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd | ForEach-Object { $_.Source } }
    foreach ($root in '.vscode\extensions', '.cursor\extensions', '.vscode-insiders\extensions') {
        Get-ChildItem (Join-Path $HOME $root) -Directory -Filter 'anthropic.claude-code-*' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'resources\native-binary\claude.exe' } |
            Where-Object { Test-Path $_ } | ForEach-Object { $cands += $_ }
    }
    if (-not $cands) { throw 'ไม่พบ claude.exe (ติดตั้ง Claude Code CLI หรือส่วนขยาย Claude Code ใน VS Code ก่อน)' }
    $cands | Select-Object -Unique | Sort-Object { Get-ClaudeVersion $_ } -Descending | Select-Object -First 1
}

function Get-CodexThreads {
    # ในไฟล์ใหม่สุดอยู่ท้าย · คืนใหม่สุดก่อน แชทละแถว
    $f = Join-Path $CodexHome 'session_index.jsonl'
    if (-not (Test-Path $f)) { return @() }
    $rows = @{}
    foreach ($line in Get-Content $f -Encoding UTF8) {
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if ($o -and $o.id) { $rows[[string]$o.id] = $o }
    }
    $rows.Values | Sort-Object updated_at -Descending
}

function Resolve-CodexThread([string]$Thread) {
    if ($Thread -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $Thread }
    $hit = @(Get-CodexThreads | Where-Object { $_.thread_name -eq $Thread })
    if ($hit.Count -eq 1) { return $hit[0].id }
    if ($hit.Count -gt 1) { throw "มีแชท Codex ชื่อ '$Thread' มากกว่า 1 อัน ให้ใช้ id แทน" }
    throw "ไม่พบแชท Codex ชื่อ '$Thread' (ดูรายชื่อด้วย ai-send.ps1 -To codex -List)"
}

function Find-CodexRollout([string]$Id) {
    Get-ChildItem (Join-Path $CodexHome 'sessions') -Recurse -Filter "rollout-*-$Id.jsonl" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# PS 5.1 ไม่ escape " ในอาร์กิวเมนต์ของโปรแกรมภายนอก: \ ที่อยู่หน้า " และ \ ท้ายข้อความต้องเพิ่มเป็นสองเท่า แล้ว " เป็น \"
function Protect-NativeArg([string]$s) { ($s -replace '(\\+)(?=")', '$1$1' -replace '(\\+)$', '$1$1') -replace '"', '\"' }
