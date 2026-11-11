# ตัวส่งระดับล่าง: ส่งข้อความเข้าแชท Claude Code ที่เปิดอยู่ (VS Code หรือ CLI) ตามชื่อแชท
# วิธี: เปิด Claude ชั่วคราว (claude -p, haiku) ให้เรียก ListAgents + SendMessage แล้วปิดตัว
# แชทปลายทางเห็นเป็น cross-session message · ตัวส่งชั่วคราวปิดไปแล้ว ตอบกลับด้วย SendMessage จะไม่ถึง ต้องตอบผ่าน ai-send.ps1
# ตัวส่งเป็น LLM จึงไม่เชื่อแค่คำว่า SENT: อ่าน stream-json แล้วตรวจว่ามีการเรียก SendMessage จริง ถึงแชทที่ถูก
# ด้วยข้อความตรงกับต้นฉบับทุกตัวอักษร และเครื่องมือตอบว่าสำเร็จ
# ปกติเรียกผ่าน ai-send.ps1 -To claude ซึ่งใส่หัวข้อความ AI-BRIDGE ให้
# ใช้:  & send-to-claude.ps1 -List
#       & send-to-claude.ps1 -To <ชื่อแชท เช่น efin-32> -TextFile <utf8>
# exit code: 0 ส่งถึงแล้ว · 1 ไม่ถึง
param(
    [string]$To,
    [string]$Text,
    [string]$TextFile,
    [string]$Model = 'haiku',
    [switch]$List
)
. (Join-Path $PSScriptRoot 'cc-common.ps1')
$claude = Find-Claude

function Invoke-Headless([string]$prompt, [string]$tools, [string]$format) {
    $argv = @('-p', '--model', $Model, '--tools', $tools, '--max-turns', '6', '--output-format', $format)
    if ($format -eq 'stream-json') { $argv += '--verbose' }
    Invoke-Native $claude $argv $prompt
}

if ($List) {
    $r = Invoke-Headless 'Call ListAgents once and print its output verbatim. Do nothing else.' 'ListAgents' 'text'
    $r.Out
    'ชื่อแชท Claude ที่ส่งถึงได้คือชื่อใน Peer sessions (เช่น efin-32) ไม่ใช่ชื่อในบรรทัด This session (นั่นคือตัวส่งชั่วคราว)'
    exit $r.Code
}
if (-not $To) { throw 'ต้องระบุ -To (ชื่อแชท Claude) · ดูรายชื่อด้วย -List' }
if ($TextFile) { $Text = [IO.File]::ReadAllText((Convert-Path -LiteralPath $TextFile), [Text.Encoding]::UTF8) }
if (-not $Text) { throw 'ต้องระบุ -Text หรือ -TextFile' }

$prompt = @"
You are a message courier authorized by the user. Do exactly this and nothing else:
1. Call ListAgents. If no peer session is named exactly "$To", print NOT_FOUND and the ListAgents output, then stop.
2. Call SendMessage with to="$To" and message equal to the text between <<<BEGIN>>> and <<<END>>> copied exactly, without the markers.
3. Print SENT and stop. Do not wait for a reply. Do not message any other session. Do not use any other tool.
<<<BEGIN>>>
$Text
<<<END>>>
"@
$r = Invoke-Headless $prompt 'ListAgents,SendMessage' 'stream-json'

# หา tool_use ของ SendMessage และผลของมัน
$norm = { param($s) (([string]$s) -replace "`r`n", "`n").Trim() }
$want = & $norm $Text
$calls = @{}; $results = @{}; $final = ''
foreach ($line in $r.Out) {
    if ($line -notmatch '^\s*\{') { continue }
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if ($o.type -eq 'assistant') {
        foreach ($c in @($o.message.content)) { if ($c.type -eq 'tool_use' -and $c.name -eq 'SendMessage') { $calls[$c.id] = $c.input } }
    } elseif ($o.type -eq 'user') {
        foreach ($c in @($o.message.content)) { if ($c.type -eq 'tool_result') { $results[$c.tool_use_id] = $c } }
    } elseif ($o.type -eq 'result') { $final = [string]$o.result }
}
$ok = $false; $altered = $false; $why = 'ตัวส่งไม่ได้เรียก SendMessage (claude.exe รุ่นเก่าที่ไม่มีเครื่องมือนี้ หรือรันใน sandbox)'
foreach ($k in $calls.Keys) {
    $in = $calls[$k]
    # ListAgents แสดงชื่อเป็น "efin-32 [e1cae5]" ตัวส่งอาจใช้ชื่อแบบมี [ref] ต่อท้าย ซึ่ง SendMessage รับได้และถึงแชทเดียวกัน
    if ([string]$in.to -notmatch "^\s*$([regex]::Escape($To))(\s*\[[0-9a-f]+\])?\s*$") { $why = "ตัวส่งเรียก SendMessage ไปที่ '$($in.to)' ไม่ใช่ '$To'"; continue }
    $res = $results[$k]
    $resText = if ($res) { (@($res.content) | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.text } }) -join ' ' } else { '' }
    if (-not $res -or $res.is_error -or $resText -match '(?i)"success"\s*:\s*false|not found|error') { $why = "SendMessage ไม่สำเร็จ: $resText"; continue }
    $ok = $true
    # ถึงแล้วแต่ข้อความไม่ตรงต้นฉบับ: ไม่นับว่าล้มเหลว (ส่งซ้ำจะได้ข้อความซ้ำ) แต่เตือนให้รู้
    $altered = ((& $norm $in.message) -replace '\s+', ' ') -cne ($want -replace '\s+', ' ')
}
if (-not $ok) {
    if ($final -match 'NOT_FOUND') { $why = "ไม่พบแชท Claude ชื่อ $To (ชื่อเปลี่ยนเมื่อเปิดแชทใหม่ · ดูรายชื่อด้วย -List)" }
    Write-Output "ERROR: ส่งไม่ถึง: $why"
    if ($r.Code -ne 0) { Write-Output "(claude -p exit $($r.Code))" }
    exit 1
}
"ส่งแล้ว -> แชท Claude $To"
if ($altered) { 'WARN: ตัวส่งคัดลอกข้อความไม่ตรงต้นฉบับทุกตัวอักษร ข้อความถึงปลายทางแล้วแต่อาจคลาดเคลื่อน (อย่าส่งซ้ำ ถ้าสำคัญให้ส่งข้อความแก้ไขตาม)' }
exit 0
