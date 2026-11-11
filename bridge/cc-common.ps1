# ฟังก์ชันกลางของฝั่ง Codex และ Claude Code (หา exe, รายชื่อแชท Codex, ไฟล์ประวัติ) · ai-bridge
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }

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
    $v = (& $exe --version 2>$null | Select-Object -First 1) -as [string]
    if ($v -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return [version]'0.0.0'
}

function Find-Claude {
    # newest wins: an old claude.exe on PATH may lack ListAgents/SendMessage
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
    # newest last in the file; return newest first, one row per id
    $f = Join-Path $CodexHome 'session_index.jsonl'
    if (-not (Test-Path $f)) { return @() }
    $rows = @{}
    foreach ($line in Get-Content $f -Encoding UTF8) {
        try { $o = $line | ConvertFrom-Json } catch { continue }
        $rows[$o.id] = $o
    }
    $rows.Values | Sort-Object updated_at -Descending
}

function Resolve-CodexThread([string]$Thread) {
    if ($Thread -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $Thread }
    $hit = @(Get-CodexThreads | Where-Object { $_.thread_name -eq $Thread })
    if ($hit.Count -eq 1) { return $hit[0].id }
    if ($hit.Count -gt 1) { throw "มีแชท Codex ชื่อ '$Thread' มากกว่า 1 อัน ให้ใช้ id แทน" }
    throw "ไม่พบแชท Codex ชื่อ '$Thread' (ดูรายชื่อด้วย send-to-codex.ps1 -List)"
}

function Find-CodexRollout([string]$Id) {
    Get-ChildItem (Join-Path $CodexHome 'sessions') -Recurse -Filter "rollout-*-$Id.jsonl" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# Windows PowerShell 5.1 does not escape " inside native arguments
function Protect-NativeArg([string]$s) { $s -replace '\\(?=\\*")', '\\' -replace '"', '\"' }
