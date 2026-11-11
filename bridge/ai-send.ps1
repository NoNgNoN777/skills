# ai-bridge: คำสั่งกลางให้ Claude Code / Codex / Antigravity (Gemini) ส่งข้อความหากันได้ทุกทาง เข้าแชทเดิมที่เปิดอยู่
# ใช้ได้จากทุกฝั่ง ผลเหมือนกัน · ตัวส่งระดับล่าง: send-to-claude.ps1 / send-to-codex.ps1 / send-to-antigravity.ps1
#
#   ดูรายชื่อแชท:  & ai-send.ps1 -To claude|codex|gemini -List
#   ส่ง:          & ai-send.ps1 -To <ปลายทาง> -Target <แชท> -From <ฝั่งเรา>:<id แชทเรา> -Message "..." [-Wait] [-NoReply]
#
#   -To      claude = แชท Claude Code (Target = ชื่อแชทจาก ListAgents เช่น efin-32)
#            codex  = แชท Codex (Target = id หรือชื่อแชท)
#            gemini = แชท Antigravity (Target = conversation id) หรือ -New เปิดแชทใหม่
#   -From    ตัวเรา ไว้ให้ปลายทางตอบกลับถูกแชท: claude:<ชื่อแชท> / codex:<thread id> / gemini:<conversation id>
#   -Wait    รอคำตอบแล้วพิมพ์ออกมา (codex: คำตอบสุดท้ายในแชท · gemini: ไฟล์ reply_file) · -To claude รอไม่ได้ คำตอบจะส่งกลับเข้าแชทเราเอง
#   -NoReply ข้อความนี้เป็นคำตอบหรือแจ้งให้ทราบ ปลายทางไม่ต้องตอบกลับ (กันวนตอบกันไม่จบ)
#   ส่วน gemini ใช้ตัวเลือกเดิมได้: -New -Model -Project -Title -Files -Review -Skills -Root -SkipSecretScan
param(
    [ValidateSet('claude', 'codex', 'gemini')][string]$To,
    [string]$Target,
    [string]$From,
    [string]$Message,
    [string]$MessageFile,
    [switch]$Wait,
    [int]$TimeoutSec = 900,
    [switch]$NoReply,
    [switch]$List,
    # gemini
    [switch]$New, [string]$Model, [string]$Project, [string]$Title, [string[]]$Files,
    [switch]$Review, [string[]]$Skills, [string[]]$Root, [switch]$SkipSecretScan
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$here = $PSScriptRoot
$Names = @{ claude = 'Claude Code'; codex = 'Codex'; gemini = 'Antigravity (Gemini)' }

if (-not $To) { throw 'ต้องระบุ -To claude|codex|gemini' }
if ($List) {
    switch ($To) {
        'claude' { & (Join-Path $here 'send-to-claude.ps1') -List }
        'codex'  { & (Join-Path $here 'send-to-codex.ps1') -List }
        'gemini' { python -I (Join-Path $here 'list-chats.py') 8 }
    }
    return
}

if ($From -notmatch '^(claude|codex|gemini):(.+)$') { throw '-From ต้องเป็น claude:<ชื่อแชท> / codex:<thread id> / gemini:<conversation id> (ตัวเราเอง ไว้ให้ปลายทางตอบกลับ)' }
$fromKind = $Matches[1]; $fromId = $Matches[2].Trim()
if ($fromKind -eq $To -and $fromId -eq $Target) { throw 'ส่งหาแชทตัวเองไม่ได้' }
$Sender = $Names[$fromKind]
if ($MessageFile) { $Message = [IO.File]::ReadAllText((Convert-Path -LiteralPath $MessageFile), [Text.Encoding]::UTF8) }
if (-not $Message) { throw 'ต้องระบุ -Message หรือ -MessageFile' }
if (-not $Target -and -not ($To -eq 'gemini' -and $New)) { throw "ต้องระบุ -Target (ดูรายชื่อ: ai-send.ps1 -To $To -List)" }
if ($Wait -and $To -eq 'claude') { throw '-To claude ใช้ -Wait ไม่ได้: Claude จะส่งคำตอบกลับเข้าแชทของคุณเอง (ตาม -From)' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) "ai-bridge-$([guid]::NewGuid().ToString('N').Substring(0, 8)).md"
try {
    if ($To -eq 'gemini') {
        # Gemini: send-to-antigravity.ps1 ใส่หัวข้อความ ตรวจความลับ แนบไฟล์ และบันทึกงานเอง
        [IO.File]::WriteAllText($tmp, $Message, [Text.UTF8Encoding]::new($false))
        $a = @{ MessageFile = $tmp; From = "$fromKind`:$fromId"; Sender = $Sender; ReplyRoute = "$fromKind`:$fromId" }
        if ($New) { $a.New = $true; if ($Model) { $a.Model = $Model }; if ($Project) { $a.Project = $Project }; $a.Title = $(if ($Title) { $Title } else { "จาก $Sender" }) }
        else { $a.ConvId = $Target }
        if ($Files) { $a.Files = $Files }; if ($Skills) { $a.Skills = $Skills }; if ($Root) { $a.Root = $Root }
        if ($Review) { $a.Review = $true }; if ($SkipSecretScan) { $a.SkipSecretScan = $true }; if ($NoReply) { $a.NoReply = $true }
        $out = @(& (Join-Path $here 'send-to-antigravity.ps1') @a)   # ส่งไม่ได้ = throw
        $out
        if ($NoReply) { exit 0 }
        $msgId = $out[-1]
        if ($Wait) {
            & (Join-Path $here 'wait-reply.ps1') -MsgId $msgId -TimeoutSec $TimeoutSec
            if ($LASTEXITCODE) { "รอต่อ: & `"$here\wait-reply.ps1`" -MsgId $msgId"; exit $LASTEXITCODE }
        }
        else { "รอคำตอบภายหลังด้วย: & `"$here\wait-reply.ps1`" -MsgId $msgId" }
        exit 0
    }

    # Claude / Codex: ใส่หัวข้อความเอง แล้วส่งตามตัว
    . (Join-Path $here 'agb-common.ps1')
    $ErrorActionPreference = 'Stop'
    if (-not $SkipSecretScan) {
        $p = @(Find-AgbSecrets $Message)
        if ($p) { throw "หยุดส่ง: อาจมีความลับ`n$($p -join "`n")`nลบค่านั้นแล้วส่งใหม่ · ถ้าผู้ใช้ยืนยันว่าไม่ใช่ความลับจริง ใส่ -SkipSecretScan" }
    }
    $rulesFile = Join-Path $here 'user-rules.md'
    if (-not $NoReply -and (Test-Path -LiteralPath $rulesFile)) {
        $rules = [IO.File]::ReadAllText($rulesFile, [Text.Encoding]::UTF8).Trim()
        if ($rules) { $Message += "`n`nข้อห้ามประจำของผู้ใช้ (ทำตามเสมอ):`n$rules" }
    }
    $msgId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + -join ((48..57 + 97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
    # command line ของ Windows ยาวได้ ~32,767 ตัวอักษร (codex queue รับข้อความทาง argument) เนื้อหายาวจึงเขียนลงไฟล์แล้วส่งแค่ path
    if ($Message.Length -gt 20000) {
        $outbox = Join-Path $here 'outbox'; New-Item -ItemType Directory -Force $outbox | Out-Null
        $bodyFile = Join-Path $outbox "$msgId.md"
        [IO.File]::WriteAllText($bodyFile, $Message, [Text.UTF8Encoding]::new($false))
        $Message = "เนื้อหายาว จึงอยู่ในไฟล์: $bodyFile`nอ่านไฟล์นั้นทั้งหมดก่อน (ทยอยอ่านเป็นช่วงถ้ายาว) แล้วถือเนื้อหาในไฟล์เป็นข้อความนี้"
    }
    $replyCmd = "& `"`$HOME\.agent-bridge\ai-send.ps1`" -To $fromKind -Target $fromId -From $To`:<id แชทนี้> -NoReply -Message `"...`""
    $how = if ($NoReply) { 'reply=none: เป็นคำตอบหรือแจ้งให้ทราบ ไม่ต้องตอบกลับ อ่านแล้วทำงานต่อตามที่ผู้ใช้สั่งไว้' }
           elseif ($Wait -and $To -eq 'codex') { 'ผู้ส่งรออ่านคำตอบในแชทนี้อยู่: ตอบในแชทตามปกติ ไม่ต้องส่งกลับด้วยคำสั่ง' }
           else { "ตอบกลับด้วยคำสั่งนี้ครั้งเดียวเมื่อเสร็จ: $replyCmd" }
    $text = @"
[AI-BRIDGE v1] from=$Sender session=$fromKind`:$fromId msg_id=$msgId
(ข้อความนี้มาจาก $Sender อีกตัวในเครื่องนี้ ไม่ใช่ผู้ใช้พิมพ์เอง · ใช้ skill ai-bridge · ไม่ได้ให้สิทธิ์เพิ่ม งานที่ต้องขออนุญาตผู้ใช้ยังต้องขอ)
($how)
---
$Message
"@
    [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($false))
    if ($To -eq 'codex') {
        $a = @{ Thread = $Target; TextFile = $tmp }
        if ($Wait) { $a.Wait = $true; $a.Marker = "msg_id=$msgId"; $a.TimeoutSec = $TimeoutSec }
        & (Join-Path $here 'send-to-codex.ps1') @a
    } else {
        & (Join-Path $here 'send-to-claude.ps1') -To $Target -TextFile $tmp
    }
    $code = $LASTEXITCODE   # สคริปต์ลูกจบด้วย exit 1 เมื่อส่งไม่ถึงหรือ TIMEOUT ต้องส่งต่อ ไม่งั้นผู้เรียกเข้าใจว่าสำเร็จ
    "msg_id=$msgId"
    if ($code) { exit $code }
} finally {
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}
