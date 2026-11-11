# แยกไฟล์จากไฟล์ติดตั้ง agent-bridge แล้ววางตามตำแหน่ง (~ = $HOME)
# ไฟล์ที่เนื้อหาเหมือนเดิมจะข้าม · ไฟล์ที่ต่างจะสำรองไว้ใน ~/.agent-bridge/backup/<เวลา>/ ก่อนเขียนทับ (ไม่วาง .bak ข้าง SKILL.md)
# ไม่แตะไฟล์ของผู้ใช้: override.json, user-rules.md, config.json, to-claude\
# ใช้:  & install-agb.ps1 -Installer <path ของไฟล์ติดตั้ง .md> [-DryRun] [-Root <โฟลเดอร์ทดสอบแทน $HOME>]
param([Parameter(Mandatory)][string]$Installer, [switch]$DryRun, [string]$Root = $HOME)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$src = [IO.File]::ReadAllText((Convert-Path -LiteralPath $Installer), [Text.Encoding]::UTF8)   # LiteralPath: ชื่อโฟลเดอร์ที่มี [ ] ไม่พัง
$ver = if ($src -match 'AGB-VERSION:\s*(\S+)') { $Matches[1] } else { '?' }
$pat = '(?s)<!-- AGB-FILE path="([^"]+)" bom="(yes|no)" -->[ \t]*\r?\n````[a-z]*[ \t]*\r?\n(.*?)\r?\n````[ \t]*\r?\n<!-- AGB-END -->'
$blocks = [regex]::Matches($src, $pat)
$want = if ($src -match 'AGB-COUNT:\s*(\d+)') { [int]$Matches[1] } else { -1 }
if ($want -lt 1 -or $blocks.Count -ne $want) { throw "ไฟล์ติดตั้งควรมี $want ไฟล์ แต่เจอ $($blocks.Count) (ไฟล์อาจถูกตัดหรือแก้รูปแบบ AGB-FILE) · ดาวน์โหลดไฟล์ติดตั้งใหม่" }
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$bakDir = Join-Path $Root ".agent-bridge\backup\$stamp"
$n = 0
Write-Output "agent-bridge รุ่น $ver"
foreach ($b in $blocks) {
    $rel  = $b.Groups[1].Value
    $dest = if ($rel.StartsWith('~/')) { Join-Path $Root ($rel.Substring(2) -replace '/', '\') } else { throw "path ต้องขึ้นต้นด้วย ~/ : $rel" }
    $body = ($b.Groups[3].Value -replace "`r?`n", "`r`n") + "`r`n"
    $enc  = New-Object Text.UTF8Encoding ($b.Groups[2].Value -eq 'yes')
    $same = (Test-Path -LiteralPath $dest) -and ([IO.File]::ReadAllText($dest, [Text.Encoding]::UTF8) -ceq $body.TrimStart([char]0xFEFF))
    if ($same) { Write-Output "เหมือนเดิม ข้าม: $dest"; continue }
    if ($DryRun) { Write-Output "จะเขียน: $dest ($([Text.Encoding]::UTF8.GetByteCount($body)) ไบต์)$(if (Test-Path -LiteralPath $dest) { ' (เขียนทับ มีสำรอง)' })"; continue }
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    if (Test-Path -LiteralPath $dest) {
        $bak = Join-Path $bakDir ($rel.Substring(2) -replace '[\\/]', '_')
        New-Item -ItemType Directory -Force $bakDir | Out-Null
        Copy-Item -LiteralPath $dest $bak; Write-Output "สำรองไฟล์เดิม: $bak"
    }
    [IO.File]::WriteAllText($dest, $body, $enc)
    Write-Output "เขียนแล้ว: $dest"; $n++
}
# ไฟล์ .bak-* จากตัวติดตั้งรุ่นก่อนที่วางข้างไฟล์จริง ย้ายไปไว้ใน backup\ ด้วย
if (-not $DryRun) {
    foreach ($b in $blocks) {
        $dest = Join-Path $Root ($b.Groups[1].Value.Substring(2) -replace '/', '\')
        foreach ($old in @(Get-ChildItem -LiteralPath (Split-Path $dest) -Filter "$(Split-Path $dest -Leaf).bak-*" -ErrorAction SilentlyContinue)) {
            $to = Join-Path $Root ".agent-bridge\backup\$($old.Name -replace '^.*\.bak-', '')"
            New-Item -ItemType Directory -Force $to | Out-Null
            Move-Item -LiteralPath $old.FullName (Join-Path $to ($b.Groups[1].Value.Substring(2) -replace '[\\/]', '_')) -Force
            Write-Output "ย้ายไฟล์สำรองเก่า: $($old.FullName) -> $to"
        }
    }
}
# skill รุ่นเก่าที่รวมเป็น ai-bridge แล้ว: ย้ายไป backup\ (ไม่ลบ) ไม่งั้นจะมี skill ซ้ำกันสองตัว
foreach ($rel in '.claude\skills\antigravity-bridge', '.gemini\config\skills\claude-bridge', '.claude\skills\claude-codex-bridge', '.codex\skills\claude-codex-bridge') {
    $old = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $old)) { continue }
    if ($DryRun) { Write-Output "จะย้าย skill รุ่นเก่าไป backup: $old"; continue }
    $to = Join-Path $bakDir ('old-skill_' + ($rel -replace '[\\/]', '_'))
    New-Item -ItemType Directory -Force $bakDir | Out-Null
    Move-Item -LiteralPath $old $to -Force
    Write-Output "ย้าย skill รุ่นเก่าไป backup: $old -> $to"
}
if (-not $DryRun) {
    New-Item -ItemType Directory -Force (Join-Path $Root '.agent-bridge\to-claude') | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root '.agent-bridge\VERSION'), $ver, (New-Object Text.UTF8Encoding $false))
    Write-Output "ติดตั้งครบ (เขียนใหม่ $n ไฟล์) ต่อไปรัน doctor.ps1"
}
