# ส่งข้อความจาก Claude Code หรือ Codex เข้าแชท Antigravity ที่เปิดอยู่ พร้อมหัวข้อความ AI-BRIDGE ให้ Gemini รู้ว่าใครส่งและตอบกลับทางไหน
# ปกติเรียกผ่าน ai-send.ps1 -To gemini (ใส่ -Sender / -NoReply ให้เอง)
# ใช้:  & send-to-antigravity.ps1 -ConvId <uuid> -MessageFile <utf8.txt> [-From <ชื่อแชท Claude>] [-Files <path>,<path>] [-Skills <ชื่อ>,<ชื่อ>] [-Root <repo>] [-Review]
#       & send-to-antigravity.ps1 -New [-Model flash|pro|flash_lite] [-Title <ชื่อ>] -Project <ชื่อ> -MessageFile <utf8.txt>
# พิมพ์ msg_id ออกมาบรรทัดสุดท้าย เอาไปใช้กับ wait-reply.ps1 · ทุกครั้งที่ส่งบันทึกลง sends.jsonl (ดูงานค้างด้วย pending.ps1)
param(
    [string]$ConvId,
    [Parameter(Mandatory)][string]$MessageFile,
    [string]$From = 'claude-code',
    [switch]$New,
    [string]$Model,
    [string]$Title = 'จาก Claude Code',
    [string]$Project,  # ชื่อหรือ id ของโปรเจกต์ Antigravity (ใช้ตอน -New) ดูรายชื่อด้วย list-chats.py --projects
    [string[]]$Files,  # ไฟล์ที่ให้ Gemini เปิดอ่านเอง: ตรวจว่ามีจริง ไม่ใช่ไฟล์ความลับ แล้วแนบ path เต็ม ขนาด และจำนวนบรรทัดท้ายบรีฟ
    [switch]$Review,   # งานรีวิว/ตรวจสอบ: บังคับให้ทุกข้อค้นพบมีความรุนแรง ความมั่นใจ และหลักฐาน path:line
    [string[]]$Skills, # skill ที่ Gemini ต้องอ่านก่อนเริ่ม: ชื่อ skill ของ Claude (ui-compare-pw, mattpocock-skills:grilling) หรือ path ของ SKILL.md / โฟลเดอร์ skill
    [string[]]$Root,   # root ของ repo ที่ใช้ตีความ path แบบ relative ในคำตอบ (ปกติหาเองจากไฟล์แนบ + โฟลเดอร์ปัจจุบัน)
    [switch]$SkipSecretScan,  # ข้ามตัวตรวจความลับ · ใช้เมื่อผู้ใช้ยืนยันแล้วว่าที่เจอไม่ใช่ความลับจริงเท่านั้น
    [string]$Sender = 'Claude Code',  # ใครส่ง: Claude Code / Codex (ai-send.ps1 ใส่ให้)
    [string]$ReplyRoute,      # ช่องทางส่งกลับหาผู้ส่ง เช่น claude:efin-32 / codex:<thread id> (ใช้กับ -NoReply ให้ Gemini ส่งต่อได้ถ้าจำเป็น)
    [switch]$NoReply          # ข้อความนี้เป็นคำตอบหรือแจ้งให้ทราบ: Gemini ไม่ต้องเขียน reply_file
)
. (Join-Path $PSScriptRoot 'agb-common.ps1')
if (-not $New -and -not $ConvId) { throw 'ต้องใส่ -ConvId หรือ -New' }

$body = [IO.File]::ReadAllText((Convert-Path -LiteralPath $MessageFile), [Text.Encoding]::UTF8)
# ตรวจความลับก่อนส่งข้ามไปอีกระบบ · บอกแค่ชนิดกับบรรทัด ไม่พิมพ์ค่าที่เจอ
$problems = @()
if (-not $SkipSecretScan) { $problems += Find-AgbSecrets $body | ForEach-Object { "บรีฟ $_" } }

# ไฟล์แนบ: Gemini อ่านเองด้วย read_file จึงส่งแค่ path ไม่ว่าไฟล์จะใหญ่แค่ไหน · ไฟล์ข้อความไม่เกิน 2 MB สแกนความลับด้วย
$attach = @()
foreach ($p in $Files) {
    if (-not $p) { continue }
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "ไม่พบไฟล์แนบ: $p" }
    $fi = Get-Item -LiteralPath $p
    if (-not $SkipSecretScan -and $fi.Name -match $AgbBlockedFile) { $problems += "ไฟล์ $($fi.FullName): ชื่อไฟล์บอกว่าเก็บความลับ" }
    $lines = $null
    if ($fi.Length -le 2MB -and $fi.Extension -notmatch '(?i)^\.(png|jpe?g|gif|webp|bmp|ico|pdf|zip|7z|rar|exe|dll|mp[34]|wav|mov|docx?|xlsx?|pptx?)$') {
        $txt = [IO.File]::ReadAllText($fi.FullName, [Text.Encoding]::UTF8)
        $lines = ($txt -split '\r?\n').Count
        if (-not $SkipSecretScan) { $problems += Find-AgbSecrets $txt | ForEach-Object { "ไฟล์ $($fi.Name) $_" } }
    }
    $size = if ($fi.Length -ge 1MB) { '{0:N1} MB' -f ($fi.Length / 1MB) } else { '{0:N0} KB' -f [Math]::Ceiling($fi.Length / 1KB) }
    $attach += "- $($fi.FullName) ($size$(if ($lines) { " · $lines บรรทัด" }))"
}
if ($problems) {
    throw "หยุดส่ง: อาจมีความลับ`n$($problems -join "`n")`nลบหรือปิดค่าเหล่านั้น หรือเอาไฟล์นั้นออกแล้วส่งใหม่ · ถ้าผู้ใช้ยืนยันว่าไม่ใช่ความลับจริง ใส่ -SkipSecretScan"
}
if ($attach) { $body += "`n`nไฟล์ที่เกี่ยวข้อง (เปิดอ่านเองด้วย read_file · ไฟล์เกิน ~800 บรรทัดให้ทยอยอ่านเป็นช่วง):`n$($attach -join "`n")" }

# skill ของ Claude ที่ให้ Gemini อ่านแล้วทำตาม: ส่งแค่ path ของ SKILL.md (ไฟล์อ้างอิงที่ skill ชี้ไป Gemini เปิดเองเมื่อถึงขั้นนั้น)
$skillLines = @()
foreach ($s in $Skills) {
    if (-not $s) { continue }
    $md = $null
    if (Test-Path -LiteralPath $s -PathType Leaf) { $md = (Get-Item -LiteralPath $s).FullName }
    elseif (Test-Path -LiteralPath (Join-Path $s 'SKILL.md')) { $md = (Get-Item -LiteralPath (Join-Path $s 'SKILL.md')).FullName }
    else {
        $name = ($s -split ':')[-1]   # plugin:skill → skill
        $cands = @(Join-Path $HOME ".claude\skills\$name\SKILL.md") +
                 @(Get-ChildItem (Join-Path $HOME '.claude\skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName "$name\SKILL.md" }) +
                 @(Get-ChildItem (Join-Path $HOME '.claude\plugins\cache') -Recurse -Filter SKILL.md -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -eq $name } | ForEach-Object FullName)
        $md = $cands | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    }
    if (-not $md) { throw "ไม่พบ skill: $s (ใส่ชื่อโฟลเดอร์ skill หรือ path ของ SKILL.md)" }
    $skillLines += "- $s → $md"
}
if ($skillLines) {
    $body = "skill ที่ต้องอ่านก่อนเริ่มงาน (เปิด SKILL.md ด้วย read_file ให้จบ แล้วทำงานตามขั้นตอนและกติกาใน skill · ไฟล์อ้างอิงที่ skill ชี้ไป เปิดเมื่อถึงขั้นนั้น · ขั้นที่ต้องใช้เครื่องมือที่ Antigravity ไม่มี ให้ทำส่วนที่ทำได้แล้วบอกในคำตอบว่าข้ามขั้นไหนเพราะอะไร):`n$($skillLines -join "`n")`n`n" + $body
}
# root สำหรับตรวจหลักฐานตอนรับคำตอบ (wait-reply.ps1 อ่านจาก sends.jsonl)
$roots = @(Get-AgbRepoRoots (@($Root) + @($Files) + @((Get-Location).Path)))
if ($Review) {
    $body += "`n`nรูปแบบข้อค้นพบ (งานรีวิว บังคับทุกข้อ):`n- หัวข้อ: [ความรุนแรง สูง/กลาง/ต่ำ · ความมั่นใจ สูง/กลาง/ต่ำ] สรุป 1 บรรทัด`n- หลักฐาน: path จาก root ของ repo:line แล้วตามด้วยบล็อกโค้ดที่คัดลอกจากผล read_file รอบนี้ตรงตัว 1–5 บรรทัด · Claude เทียบบล็อกนี้กับไฟล์จริงอัตโนมัติ ข้อที่ไม่ตรงถูกตัดทิ้งทั้งข้อ (ถ้าไม่มีหลักฐานในไฟล์ ให้เขียนว่า `"ไม่มีหลักฐานตรง`" และลดความมั่นใจเป็นต่ำ)`n- ข้อที่บอกว่า `"ไม่มี`" หรือ `"ไม่พบ`": บอกคำค้นและโฟลเดอร์ที่ค้นด้วย grep_search`n- เสนอแก้: ถ้ามี`nเรียงจากความรุนแรงมากไปน้อย"
}

$pvar = Get-AgbOverride 'env_project'; if (-not $pvar) { $pvar = 'ANTIGRAVITY_PROJECT_ID' }
Remove-Item "env:$pvar" -ErrorAction SilentlyContinue   # กันค่าโปรเจกต์จากรอบก่อนค้างอยู่
if ($New -and $Project) {
    $pj = Find-AgbProject $Project
    Set-Item "env:$pvar" $pj.Id
}
New-Item -ItemType Directory -Force $AgbInbox | Out-Null
[void](Move-AgbOldReplies 14)   # คำตอบเก่ากว่า 14 วันย้ายไป to-claude\archive\ กันโฟลเดอร์บวม

$c = Connect-Agb $ConvId
if ($Model -and $c.Cmd.Models.Count -and ($c.Cmd.Models -notcontains $Model)) {
    throw "โมเดล '$Model' ไม่มีในแอปรุ่นนี้ · ที่มีตอนนี้: $($c.Cmd.Models -join ', ')"
}

$ver   = Get-AgbVersion
$msgId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + -join ((48..57 + 97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
$reply = Join-Path $AgbInbox "$msgId.md"
# ข้อห้ามประจำของผู้ใช้ (user-rules.md) แนบให้ทุกครั้ง ไม่ต้องพึ่ง AI จำ · ตัวติดตั้งไม่เขียนทับไฟล์นี้
$rulesFile = Join-Path $AgbRoot 'user-rules.md'
if (Test-Path -LiteralPath $rulesFile) {
    $rules = [IO.File]::ReadAllText($rulesFile, [Text.Encoding]::UTF8).Trim()
    if ($rules) { $body += "`n`nข้อห้ามประจำของผู้ใช้ (ทำตามเสมอ):`n$rules" }
}
# command line ของ Windows ยาวได้ไม่เกิน 32,767 ตัวอักษร ข้อความยาวจึงเขียนลงไฟล์แล้วส่งแค่ path ไป
if ($body.Length -gt 20000) {
    $outbox = Join-Path $AgbRoot 'outbox'; New-Item -ItemType Directory -Force $outbox | Out-Null
    Get-ChildItem $outbox -Filter *.md | Where-Object LastWriteTime -lt (Get-Date).AddDays(-7) | Remove-Item -ErrorAction SilentlyContinue   # ล้างของเก่าเกิน 7 วัน
    $bodyFile = Join-Path $outbox "$msgId.md"
    [IO.File]::WriteAllText($bodyFile, $body, (New-Object Text.UTF8Encoding $false))
    $body = "เนื้อหางานยาว จึงอยู่ในไฟล์: $bodyFile`nอ่านไฟล์นั้นทั้งหมดก่อน (ทยอยอ่านเป็นช่วงถ้ายาว) แล้วทำตามเนื้อหาในไฟล์เหมือนเป็นข้อความนี้"
}
if ($NoReply) {
    $route = if ($ReplyRoute -match '^(claude|codex|gemini):(.+)$') { " · ถ้าจำเป็นต้องส่งกลับจริงๆ ใช้: & `"`$HOME\.agent-bridge\ai-send.ps1`" -To $($Matches[1]) -Target $($Matches[2]) -From gemini:<id แชทนี้> -NoReply -Message `"...`"" } else { '' }
    $text = @"
[AI-BRIDGE v1] from=$Sender session=$From msg_id=$msgId agb=$ver reply=none
(ข้อความนี้มาจาก $Sender อีกตัวในเครื่องนี้ ไม่ใช่ผู้ใช้พิมพ์เอง · ใช้ skill ai-bridge · เป็นคำตอบหรือแจ้งให้ทราบ ไม่ต้องเขียน reply_file และไม่ต้องตอบกลับ อ่านแล้วทำงานต่อตามที่ผู้ใช้สั่งไว้$route)
---
$body
"@
    $reply = ''
} else {
    $text = @"
[AI-BRIDGE v1] from=$Sender session=$From msg_id=$msgId agb=$ver
reply_file=$reply
(ข้อความนี้มาจาก $Sender อีกตัวในเครื่องนี้ ไม่ใช่ผู้ใช้พิมพ์เอง · ใช้ skill ai-bridge · ตอบโดยเขียนไฟล์ reply_file ครั้งเดียวเมื่อเสร็จ แล้วสรุปสั้นๆ ในแชทนี้ด้วยหัวข้อ 📨 งานจาก $Sender`: ขอให้ทำ / ทำอะไรไป / ผลสรุป / สถานะ / คำตอบเต็ม)
(frontmatter ของ reply_file ใช้ชื่อช่องตามนี้เท่านั้น ห้ามลอกชื่อจากบรรทัดหัวข้อความ: from: Antigravity (Gemini) · conversation_id: <id แชทนี้> · in_reply_to: $msgId · status: done | partial | refused | need-user · skill_version: <รุ่นที่เขียนไว้ใน skill ai-bridge> · refused/need-user ต้องเขียนเหตุผลหรือสิ่งที่รอไว้ในเนื้อหา)
---
$body
"@
}
if ($New) {
    $argv = @('agentapi', $c.Cmd.New, "--title=$Title")
    if ($Model) { $argv += "--model=$Model" }
    $r = Invoke-Agb $c.Exe ($argv + $text)
} else {
    $r = Invoke-Agb $c.Exe @('agentapi', $c.Cmd.Send, $ConvId, $text)
}
if ($r -match '(?i)project_id is required') {
    throw "เปิดแชทใหม่ต้องระบุโปรเจกต์ · ใส่ -Project <ชื่อโปรเจกต์> (ดูรายชื่อ: python -I list-chats.py --projects)"
}
if ($r -match '"error"\s*:\s*"[^"]' -or $r -match '(?i)^usage:') { throw "ส่งไม่สำเร็จ (รูปแบบคำสั่งอาจเปลี่ยน รัน doctor.ps1): $r" }
# แชทใหม่: id ของแชทไว้ส่งรอบต่อไปเข้าแชทเดิม (ถ้าหาไม่เจอ ใช้ conversation_id ในไฟล์คำตอบแทน)
# หา UUID ที่ติดป้าย conversation ก่อน ไม่งั้นเอา UUID ตัวแรกที่ไม่ใช่ id โปรเจกต์
$uuid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
$cid = $ConvId
if ($New) {
    $cid = '?'
    if ($r -match "(?i)conv(?:ersation)?[\s_-]*id[`"'\s:=]+($uuid)") { $cid = $Matches[1] }
    else { $u = [regex]::Matches($r, $uuid) | ForEach-Object Value | Where-Object { -not $pj -or $_ -ne $pj.Id } | Select-Object -First 1; if ($u) { $cid = $u } }
}
# ผลดิบของ agentapi ครั้งล่าสุด ไว้ดูตอนรูปแบบผลลัพธ์เปลี่ยน (ไม่มีรหัส CSRF อยู่ในนี้)
# agentapi ส่งข้อความทั้งก้อนกลับมาในช่อง prompt/content จึงตัดเนื้อหาทิ้ง เก็บแค่โครงสร้างกับ id
$rlog = [regex]::Replace($r, '("(?:prompt|content)"\s*:\s*)"(?:[^"\\]|\\.)*"', '$1"(ตัดเนื้อหาออก)"')
try { [IO.File]::WriteAllText((Join-Path $AgbRoot 'last-send.log'), "$(Get-Date -Format s) new=$New conv_id=$cid`n$rlog", (New-Object Text.UTF8Encoding $false)) } catch { }
# บันทึกแค่ข้อมูลระบุงาน ไม่เก็บเนื้อหาบรีฟ
if (-not $NoReply) { Add-AgbSendLog ([ordered]@{ time = (Get-Date).ToString('s'); msg_id = $msgId; conv_id = $cid; from = $From; sender = $Sender
                            title = $(if ($New) { $Title } else { '' }); new = [bool]$New; model = $Model; project = $Project
                            review = [bool]$Review; files = @($Files | Where-Object { $_ }).Count; skills = @($Skills | Where-Object { $_ })
                            roots = $roots; agb = $ver }) }
Write-Output "port=$($c.Port) app=$($c.Version) conv_id=$cid"
Write-Output $msgId
