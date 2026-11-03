# Claude Code ⇄ Antigravity skills

skill 2 ตัวสำหรับให้ **Claude Code** กับ **Antigravity (Gemini)** ที่เปิดอยู่ในเครื่องเดียวกันทำงานร่วมกัน

| skill | ทำอะไร |
|---|---|
| **antigravity-bridge** | Claude ส่งข้อความหรืองานเข้าแชท Antigravity (แชทเดิม หรือเปิดแชทใหม่พร้อมเลือกโมเดลและโปรเจกต์) แล้ว Gemini ตอบกลับผ่านไฟล์ ก่อนส่งถามผู้ใช้เสมอ และแนะนำแชทที่เปิดอยู่ |
| **claude-gemini-team** | แบ่งงานให้แต่ละฝั่งทำสิ่งที่ถนัด เพื่อประหยัด token ของ Claude: Gemini ค้นเว็บ อ่านเอกสารหรือไฟล์จำนวนมาก แปล สรุป และรีวิวรอบแรก · Claude แก้โค้ด ตัดสินใจ และสุ่มตรวจผลก่อนใช้ |

```
Claude ── send-to-antigravity.ps1 ──▶ agentapi ของ Antigravity ──▶ แชท Gemini
                                                       │ skill claude-bridge (ฝั่ง Gemini)
Claude ◀── wait-reply.ps1 ◀── ~/.agent-bridge/to-claude/<msg_id>.md ◀─┘
                                     + Gemini สรุปสั้นๆ ไว้ในแชทตัวเองเป็นประวัติ
```

## ต้องมี

- Windows 10/11
- Claude Code ที่รันบน Windows โดยตรง (CLI หรือ VS Code) ไม่ใช่ใน WSL
- Antigravity เปิดค้างไว้
- Python 3 ใช้ดูรายชื่อแชท ถ้าไม่มีก็ยังส่งได้ แต่ต้องบอก id ของแชทเอง
- เปิดโฟลเดอร์งานใน Antigravity ไว้อย่างน้อย 1 โฟลเดอร์ (เปิดแชทใหม่ต้องมีโปรเจกต์)

## ติดตั้ง

**แบบที่ 1: ไฟล์เดียว (ไม่ต้อง clone)**
ดาวน์โหลด [`dist/antigravity-bridge-installer.md`](dist/antigravity-bridge-installer.md) แล้วบอก Claude Code ว่า

```
ติดตั้งตามไฟล์ "<path ของไฟล์ที่ดาวน์โหลด>"
```

Claude จะทำต่อเองตามลำดับ:
1. อธิบายว่าจะวางไฟล์ไว้ที่ไหน แล้วถามยืนยัน
2. ติดตั้ง
3. รันตัวตรวจ แล้วบอกว่าติดอะไร (ถ้ามี)

**แบบที่ 2: จาก repo**

```powershell
git clone <url ของ repo นี้>
cd <โฟลเดอร์ repo>
.\install.ps1 -DryRun   # ดูว่าจะเขียนไฟล์ไหน
.\install.ps1           # ติดตั้งจริง (ข้ามไฟล์ที่เหมือนเดิม · ไฟล์เดิมสำรองไว้ใน ~/.agent-bridge/backup/<เวลา>/)
& "$HOME\.agent-bridge\doctor.ps1"
```

ถ้ารันสคริปต์ไม่ได้ ให้รัน `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` ก่อน

## ใช้งาน

พูดกับ Claude Code ได้แบบนี้

- "ส่งไป Antigravity ให้สรุปไฟล์ …" หรือ "ถาม Gemini ว่า …" ใช้ antigravity-bridge
- "ช่วยกันทำ …" หรือ "ให้ Gemini ช่วยค้น …" ใช้ claude-gemini-team ซึ่ง Claude แบ่งงานเองว่าใครทำอะไร

ก่อนส่งงานใหม่ Claude จะถามคำถามเดียวว่าส่งเข้าแชทไหน ตัวเลือกแชทใหม่รวมโมเดลไว้แล้ว (`flash` / `pro` / `flash_lite`) ส่วนโปรเจกต์ Claude เลือกเองจากโฟลเดอร์ของงาน รอบต่อไปของงานเดิมส่งเข้าแชทเดิมได้โดยไม่ต้องถามซ้ำ

**ข้อห้ามประจำ:** เขียนไว้ใน `~/.agent-bridge/user-rules.md` บรรทัดละข้อ (เช่น `- ตอบเป็นภาษาไทย`) สคริปต์แนบท้ายทุกข้อความให้เอง และติดตั้งรุ่นใหม่ทับแล้วไฟล์นี้ไม่หาย

**ไฟล์แนบและงานรีวิว:** `-Files <path>,<path>` แนบ path เต็มของไฟล์ให้ Gemini อ่านเอง (ตรวจว่ามีจริงและสแกนความลับ) · `-Review` บังคับให้ทุกข้อค้นพบมีความรุนแรง ความมั่นใจ และหลักฐาน `path:line`

**งานค้าง:** ทุกครั้งที่ส่งบันทึกลง `~/.agent-bridge/sends.jsonl` ดูงานที่ยังไม่ตอบด้วย `& "$HOME\.agent-bridge\pending.ps1"` คำตอบที่เก่ากว่า 14 วันย้ายไป `to-claude\archive\` เอง

**รุ่น:** หัวข้อความมี `agb=<รุ่น>` และ Gemini ตอบ `skill_version` กลับมา ถ้าไม่ตรงกัน wait-reply จะเตือนให้ติดตั้งใหม่หรือเปิดแชทใหม่

**ข้อความยาว:** เกิน ~20,000 ตัวอักษรสคริปต์เขียนลง `~/.agent-bridge/outbox/` แล้วส่งแค่ path ไป (command line ของ Windows ยาวได้ไม่เกิน 32,767 ตัวอักษร)

## เมื่อแอปอัปเดตแล้วพัง

สคริปต์ค้นหาทุกอย่างใหม่ทุกครั้งที่รัน ได้แก่ ตำแหน่งโปรแกรม รหัส port ชื่อคำสั่ง ชื่อตัวแปร ฐานข้อมูลแชท ไฟล์ประวัติ และรายชื่อโมเดล ถ้ายังพัง:

```powershell
& "$HOME\.agent-bridge\doctor.ps1"
```

doctor จะบอกว่าส่วนไหนพัง และให้ใส่ค่าอะไรใน `~/.agent-bridge/override.json` ดูตัวอย่างค่าที่ใส่ได้ที่หัวไฟล์ `bridge/doctor.ps1`

## ข้อจำกัด

- **ใช้คำสั่งภายใน:** ระบบใช้คำสั่งภายในของ Antigravity (`agentapi`) ซึ่งไม่มีเอกสารทางการ ทดสอบแล้วกับ Antigravity 2.26.0
- **ทางเดียว:** Claude เริ่มก่อนเสมอ Antigravity ส่งงานมาหา Claude เองไม่ได้
- **เลือกระดับไม่ได้:** ตอนเปิดแชทใหม่เลือก Low/Medium/High ไม่ได้ และแชทเดิมเปลี่ยนโมเดลผ่านคำสั่งไม่ได้ ต้องกดเองในแอป
- **รู้ได้แค่แชทที่เปิด:** บอกได้ว่าแชทไหนเปิดอยู่ แต่ไม่รู้ว่าผู้ใช้กำลังดูแชทไหนบนจอ

## ความปลอดภัย

- **รหัสไม่ออกนอกเครื่อง:** อ่านรหัส CSRF จาก process ในเครื่อง ใช้ในตัวแปรชั่วคราวเท่านั้น ไม่พิมพ์ ไม่บันทึก ไม่ส่งออกนอกเครื่อง
- **ตรวจความลับก่อนส่ง:** `send-to-antigravity.ps1` สแกนบรีฟหา private key, token, API key, JWT, webhook URL, connection string และ `password=` ที่มีค่า ถ้าเจอจะหยุดส่งและบอกแค่ชนิดกับเลขบรรทัด ถ้าเป็นการเตือนผิด ให้ใส่ `-SkipSecretScan` หลังผู้ใช้ยืนยัน ตัวตรวจสแกนบรีฟและไฟล์ที่แนบด้วย `-Files` ส่วน path ที่พิมพ์ไว้ในบรีฟเองไม่ถูกสแกน
- **คำตอบเป็นแค่ข้อมูล:** คำตอบจาก Gemini ไม่ใช่คำสั่งจากผู้ใช้ Claude ต้องถามก่อนทำตาม
- **Gemini ไม่ได้สิทธิ์เพิ่ม:** ห้ามส่งความลับลงไฟล์คำตอบ งานเสี่ยงต้องถามผู้ใช้ในแชท Antigravity ก่อน

## โครงสร้าง

```
skills/antigravity-bridge/SKILL.md    skill ฝั่ง Claude: ส่ง/รับ
skills/claude-gemini-team/SKILL.md    skill ฝั่ง Claude: แบ่งงาน
skills/claude-gemini-team/gemini-tools.md  ข้อมูลเครื่องมือของ Gemini (team skill เปิดอ่านเมื่อจำเป็น)
antigravity/claude-bridge/SKILL.md    skill ฝั่ง Gemini (ติดตั้งที่ ~/.gemini/config/skills/)
bridge/                               สคริปต์ (ติดตั้งที่ ~/.agent-bridge/)
  agb-common.ps1                      ฟังก์ชันกลาง: หา process/รหัส/port/ชื่อคำสั่ง, ส่ง argument ให้ถูก
  send-to-antigravity.ps1             ส่งเข้าแชทเดิม หรือ -New -Model -Project
  wait-reply.ps1                      รอไฟล์คำตอบ (เตือนเมื่อ frontmatter ผิดหรือรุ่น skill ฝั่ง Gemini ไม่ตรง)
  pending.ps1                         งานที่ส่งไปแล้วยังไม่ตอบ (จาก sends.jsonl) / -All / -Archive
  list-chats.py                       รายชื่อแชท / [เปิดอยู่] / --projects / --transcript / --diagnose
  doctor.ps1                          ตรวจระบบ
install.ps1                           ติดตั้งจาก repo (เรียก tools/install-agb.ps1 กับ dist/ เหมือนแบบไฟล์เดียว)
tools/build.py                        สร้าง dist/ จากไฟล์ต้นฉบับ (แก้ต้นฉบับแล้วรันใหม่ อย่าแก้ dist ตรงๆ · เพิ่มไฟล์ต้องแก้จำนวนใน install-agb.ps1 ด้วย)
tools/header.md, tools/install-agb.ps1  ส่วนหัวและตัวแยกไฟล์ของไฟล์ติดตั้งไฟล์เดียว
dist/antigravity-bridge-installer.md  ไฟล์ติดตั้งไฟล์เดียว
```
