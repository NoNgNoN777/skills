# ตัวส่งระดับล่าง: ส่งข้อความเข้าแชท Claude Code ที่เปิดอยู่ (VS Code หรือ CLI) ตามชื่อแชท
# วิธี: เปิด Claude ชั่วคราว (claude -p, haiku) ให้เรียก ListAgents + SendMessage แล้วปิดตัว
# แชทปลายทางเห็นเป็น cross-session message · ตัวส่งชั่วคราวปิดไปแล้ว ตอบกลับด้วย SendMessage จะไม่ถึง ต้องตอบผ่าน ai-send.ps1
# ปกติเรียกผ่าน ai-send.ps1 -To claude ซึ่งใส่หัวข้อความ AI-BRIDGE ให้
# ใช้:  & send-to-claude.ps1 -List
#       & send-to-claude.ps1 -To <ชื่อแชท เช่น efin-32> -TextFile <utf8>
param(
    [string]$To,
    [string]$Text,
    [string]$TextFile,
    [string]$Model = 'haiku',
    [switch]$List
)
. (Join-Path $PSScriptRoot 'cc-common.ps1')
$claude = Find-Claude

function Invoke-Headless([string]$prompt, [string]$tools) {
    $prompt | & $claude -p --model $Model --tools $tools --max-turns 6 --output-format text 2>&1 | ForEach-Object { "$_" }
}

if ($List) {
    Invoke-Headless 'Call ListAgents once and print its output verbatim. Do nothing else.' 'ListAgents'
    'ชื่อแชท Claude ที่ส่งถึงได้คือชื่อใน Peer sessions (เช่น efin-32) ไม่ใช่ชื่อในบรรทัด This session (นั่นคือตัวส่งชั่วคราว)'
    return
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
$out = Invoke-Headless $prompt 'ListAgents,SendMessage'
$code = $LASTEXITCODE
$all = $out -join "`n"
if ($code -ne 0) { throw "claude -p ล้มเหลว (exit $code): $all" }
if ($all -match 'NOT_FOUND') { throw "ไม่พบแชท Claude ชื่อ $To (ชื่อเปลี่ยนเมื่อเปิดแชทใหม่ · ดูรายชื่อด้วย -List)`n$all" }
# ตัวส่งต้องพิมพ์ SENT หลังเรียก SendMessage จริง · claude.exe รุ่นเก่าไม่มีเครื่องมือนี้แล้วจะแต่งผลขึ้นมาเอง
if ($all -notmatch '(?m)^\W*SENT\b') { throw "ส่งไม่สำเร็จ: ตัวส่งไม่ได้ยืนยัน SENT (ถ้ารันใน sandbox ให้รันนอก sandbox)`n$all" }
"ส่งแล้ว -> แชท Claude $To"
