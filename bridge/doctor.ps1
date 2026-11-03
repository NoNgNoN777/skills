# ตรวจว่า agent-bridge ใช้ได้ไหม และชี้ว่าส่วนไหนพัง (ใช้หลังติดตั้ง และเมื่อแอปอัปเดตแล้วส่งไม่ได้)
# อ่านอย่างเดียว ยกเว้นบันทึกผลค้นล่าสุดลง config.json · ไม่ส่งข้อความเข้าแชทใดๆ · ไม่พิมพ์รหัส CSRF
# ใช้:  & doctor.ps1
# ถ้าค้นเองไม่เจอ สร้าง override.json ข้างสคริปต์ ใส่เฉพาะช่องที่ต้องการ เช่น
#   { "exe": "C:\\...\\language_server.exe", "process_hint": "subclient_type hub",
#     "env_address": "ANTIGRAVITY_LS_ADDRESS", "env_csrf": "ANTIGRAVITY_CSRF_TOKEN",
#     "cmd_meta": "get-conversation-metadata", "cmd_send": "send-message", "cmd_new": "new-conversation" }
. (Join-Path $PSScriptRoot 'agb-common.ps1')
$ErrorActionPreference = 'Continue'
$fail = 0; $warn = 0
function Ok($m)   { Write-Output "[OK]   $m" }
function Bad($m, $fix) { $script:fail++; Write-Output "[FAIL] $m"; if ($fix) { Write-Output "       วิธีแก้: $fix" } }
function Warn($m, $fix) { $script:warn++; Write-Output "[WARN] $m"; if ($fix) { Write-Output "       วิธีแก้: $fix" } }

Write-Output "== agent-bridge doctor ($AgbRoot)"

# 1. ระบบ
if ($PSVersionTable.PSVersion.Major -ge 5) { Ok "PowerShell $($PSVersionTable.PSVersion)" } else { Bad 'PowerShell ต่ำกว่า 5' 'อัปเดต Windows PowerShell' }
$pol = Get-ExecutionPolicy
if ($pol -in 'Restricted', 'AllSigned') { Bad "ExecutionPolicy = $pol (รันสคริปต์ที่สร้างเองไม่ได้)" 'ให้ผู้ใช้รันเอง: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned' } else { Ok "ExecutionPolicy = $pol" }
$py = Get-Command python -ErrorAction SilentlyContinue
# python ใน WindowsApps อาจเป็นแค่ทางลัดไป Microsoft Store ที่รันไม่ได้จริง จึงลองรันดู
$pyVer = if ($py) { try { (& python -I -c "import sys; print(sys.version.split()[0])" 2>$null | Select-Object -First 1) } catch { $null } }
if ($pyVer -match '^3\.') { Ok "Python $pyVer : $($py.Source)" }
elseif ($py) { $py = $null; Warn "คำสั่ง python มีแต่รันไม่ได้ (อาจเป็นทางลัด Microsoft Store: $((Get-Command python).Source))" 'ติดตั้ง Python 3 จาก python.org หรือปิด App execution aliases ของ python ใน Settings' }
else { Warn 'ไม่พบ python (list-chats.py ใช้ไม่ได้)' 'ติดตั้ง Python 3 หรือให้ผู้ใช้บอก conversation id เอง' }
$ver = Join-Path $AgbRoot 'VERSION'
if (Test-Path $ver) { Ok "รุ่นที่ติดตั้ง: $((Get-Content $ver -Raw).Trim())" } else { Warn 'ไม่รู้รุ่นที่ติดตั้ง (ติดตั้งด้วยตัวติดตั้งรุ่นเก่า)' 'ติดตั้งไฟล์ติดตั้งรุ่นล่าสุดทับ' }

# 2. Antigravity ที่รันอยู่
$srv = $null
try { $srv = Find-AgbServer; Ok "Antigravity รันอยู่ (รุ่น $($srv.Version)) · exe: $($srv.Exe)" }
catch { Bad $_.Exception.Message 'เปิดแอป Antigravity ค้างไว้ ถ้าเปิดอยู่แล้ว ให้ดูชื่อ process ใน Task Manager แล้วใส่ process_name_like / process_hint ใน override.json' }

if ($srv) {
    if (Test-Path $srv.Exe) { Ok 'ไฟล์โปรแกรม language server มีอยู่จริง' } else { Bad "ไม่พบไฟล์ $($srv.Exe)" 'ใส่ path ที่ถูกใน override.json ช่อง exe' }
    Ok 'อ่านรหัส CSRF จาก process ได้ (ไม่แสดงค่า)'

    # 3. คำสั่ง agentapi
    $cmds = $null
    try {
        $cmds = Resolve-AgbCommands $srv.Exe
        Ok "คำสั่ง agentapi: meta=$($cmds.Meta) send=$($cmds.Send) new=$($cmds.New)"
        if ($cmds.Models.Count) { Ok "โมเดลที่เลือกได้ตอนเปิดแชทใหม่: $($cmds.Models -join ', ')" } else { Warn 'อ่านรายชื่อโมเดลจาก --help ไม่ได้' 'เปิดแชทใหม่โดยไม่ใส่ -Model' }
        foreach ($k in 'Meta', 'Send', 'New') {
            $d = @{ Meta = 'get-conversation-metadata'; Send = 'send-message'; New = 'new-conversation' }[$k]
            if ($cmds.$k -ne $d) { Warn "คำสั่ง $d เปลี่ยนชื่อเป็น $($cmds.$k) (ระบบปรับให้อัตโนมัติแล้ว ตรวจรูปแบบ argument ใน help ด้านล่าง)" $null }
        }
    } catch {
        Bad $_.Exception.Message 'ดูรายการคำสั่งด้านล่าง แล้วใส่ชื่อที่ถูกใน override.json'
        Write-Output (Get-AgbHelp $srv.Exe)
    }

    # 4. เชื่อมต่อจริง (อ่าน metadata อย่างเดียว)
    if ($cmds) {
        try {
            $c = Connect-Agb $null
            $cfg = Read-AgbJson 'config.json'
            Ok "เชื่อมต่อ server ได้ที่ port $($c.Port) · ตัวแปร $($cfg.env_address) / $($cfg.env_csrf)"
        } catch {
            Bad $_.Exception.Message $null
            # ไล่หาชื่อตัวแปรในตัวโปรแกรม เผื่อเปลี่ยนชื่อ
            try {
                $fs = [IO.File]::OpenRead($srv.Exe); $buf = New-Object byte[] (16MB); $names = @{}
                while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
                    $s = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
                    foreach ($m in [regex]::Matches($s, '[A-Z][A-Z0-9_]{3,40}(?:LS_ADDRESS|CSRF_TOKEN)')) {
                        # ข้อความในโปรแกรมต่อกันโดยไม่มีตัวคั่น ตัดชื่อที่มีทั้งสองคำติดกันทิ้ง
                        if (-not ($m.Value -match 'LS_ADDRESS.+CSRF_TOKEN|CSRF_TOKEN.+LS_ADDRESS')) { $names[$m.Value] = 1 }
                    }
                }
                $fs.Close()
                Write-Output "       ชื่อตัวแปรที่เจอในโปรแกรม: $($names.Keys -join ', ')"
                Write-Output '       ใส่ชื่อที่ถูกใน override.json ช่อง env_address / env_csrf แล้วรัน doctor อีกครั้ง'
            } catch { }
        }
    }
    if ($cmds) { Write-Output '-- agentapi --help (ไว้ตรวจรูปแบบ argument):'; Write-Output $cmds.Help }
}

# 5. ข้อมูลแชท
$root = $null
if ($env:AGB_GEMINI_DIR) { $root = $env:AGB_GEMINI_DIR }
else { $root = Get-ChildItem "$HOME\.gemini" -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'brain') } |
       Sort-Object { $_.Name -ne 'antigravity' } | Select-Object -First 1 -ExpandProperty FullName }
if ($root) { Ok "โฟลเดอร์ข้อมูลแชท: $root" } else { Bad 'ไม่พบ ~/.gemini/*/brain' 'ตั้งตัวแปร AGB_GEMINI_DIR เป็นโฟลเดอร์ที่มี brain\ อยู่ข้างใน' }
if ($py -and $root) {
    $d = (& python -I (Join-Path $AgbRoot 'list-chats.py') --diagnose 2>&1) -join "`n"
    if ($d -match 'database\s*:\s*ไม่พบ') { Warn 'ไม่พบฐานข้อมูลรายชื่อแชท ใช้การไล่โฟลเดอร์แทน (ชื่อแชทอาจไม่ตรงกับในแอป)' $null } else { Ok 'อ่านรายชื่อแชทจากฐานข้อมูลได้' }
    if ($d -match 'presence\s*:\s*ไม่มี') { Warn 'ไม่มีโฟลเดอร์ presence (บอกไม่ได้ว่าแชทไหนเปิดอยู่)' 'ให้ผู้ใช้บอกเองว่าเปิดแชทไหนอยู่' } else { Ok 'ตรวจแชทที่เปิดอยู่ได้ (presence)' }
    $sample = (& python -I (Join-Path $AgbRoot 'list-chats.py') 1 2>&1) -join "`n"
    Write-Output "       ตัวอย่างแชทล่าสุด: $($sample.Split("`n")[0])"
    $cid = ($sample -replace '^\[[^\]]+\]\s*', '').Split(' ')[0]
    if ($cid -match '^[0-9a-f-]{36}$') {
        $t = ((& python -I (Join-Path $AgbRoot 'list-chats.py') --transcript $cid 2>&1) -join '').Trim()
        if ($t -and (Test-Path -LiteralPath $t)) { Ok "หา transcript ของแชทได้: $t" } else { Warn 'หาไฟล์ transcript.jsonl ไม่เจอ (ติดตามความคืบหน้าไม่ได้)' 'อ่านคำตอบจากไฟล์ใน to-claude\ อย่างเดียว' }
    }
}

# 5b. โปรเจกต์ (เปิดแชทใหม่ต้องระบุ)
$projects = @(Get-AgbProjects)
if ($projects.Count) { Ok "โปรเจกต์ใน Antigravity: $($projects.Count) ตัว (เปิดแชทใหม่ใช้ -Project <ชื่อ>)" }
else { Warn 'ไม่พบรายชื่อโปรเจกต์ใน ~/.gemini/*/projects/ (เปิดแชทใหม่อาจไม่ได้)' 'สร้างโปรเจกต์ในแอปก่อน หรือส่งเข้าแชทเดิมแทน' }

# 6. skill ฝั่ง Gemini
$gskill = "$HOME\.gemini\config\skills\claude-bridge\SKILL.md"
if (Test-Path $gskill) { Ok "skill ฝั่ง Gemini: $gskill" } else { Bad "ไม่พบ $gskill" 'ติดตั้งไฟล์ claude-bridge\SKILL.md ตามไฟล์ติดตั้ง' }
$docs = Get-ChildItem "$HOME\.gemini\*\builtin\skills\agy-customizations" -Recurse -Filter *.md -ErrorAction SilentlyContinue
if ($docs) {
    if ($docs | Select-String -SimpleMatch '.gemini/config/skills' -Quiet) { Ok 'เอกสารในแอปยังระบุตำแหน่ง skill ส่วนกลางที่ ~/.gemini/config/skills/' }
    else { Warn 'เอกสารในแอปไม่ได้พูดถึง ~/.gemini/config/skills/ แล้ว (ตำแหน่ง skill อาจเปลี่ยน)' "อ่าน $($docs[0].DirectoryName) หาตำแหน่ง Global skills ใหม่ แล้วย้าย claude-bridge ไปไว้ที่นั่น" }
}

# 7. skill ฝั่ง Claude + กล่องจดหมาย
$cskill = "$HOME\.claude\skills\antigravity-bridge\SKILL.md"
if (Test-Path $cskill) { Ok "skill ฝั่ง Claude: $cskill" } else { Bad "ไม่พบ $cskill" 'ติดตั้งไฟล์ antigravity-bridge\SKILL.md ตามไฟล์ติดตั้ง' }
New-Item -ItemType Directory -Force $AgbInbox | Out-Null; Ok "กล่องจดหมายคำตอบ: $AgbInbox"

Write-Output "== สรุป: FAIL $fail · WARN $warn"
if ($fail) { exit 1 } else { exit 0 }
