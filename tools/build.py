# -*- coding: utf-8 -*-
"""สร้างไฟล์ติดตั้งไฟล์เดียว dist/antigravity-bridge-installer.md จากไฟล์ใน repo
ใช้: python -I tools/build.py   (รันจากโฟลเดอร์ไหนก็ได้) · แก้ไฟล์ต้นฉบับแล้วรันใหม่ทุกครั้ง อย่าแก้ไฟล์ใน dist/ ตรงๆ"""
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = [  # (ต้นทางใน repo, ปลายทางในเครื่อง, bom, ภาษาของ code block)
    ('bridge/agb-common.ps1', '~/.agent-bridge/agb-common.ps1', 'yes', 'powershell'),
    ('bridge/send-to-antigravity.ps1', '~/.agent-bridge/send-to-antigravity.ps1', 'yes', 'powershell'),
    ('bridge/wait-reply.ps1', '~/.agent-bridge/wait-reply.ps1', 'yes', 'powershell'),
    ('bridge/doctor.ps1', '~/.agent-bridge/doctor.ps1', 'yes', 'powershell'),
    ('bridge/pending.ps1', '~/.agent-bridge/pending.ps1', 'yes', 'powershell'),
    ('bridge/list-chats.py', '~/.agent-bridge/list-chats.py', 'no', 'python'),
    ('skills/antigravity-bridge/SKILL.md', '~/.claude/skills/antigravity-bridge/SKILL.md', 'no', 'markdown'),
    ('antigravity/claude-bridge/SKILL.md', '~/.gemini/config/skills/claude-bridge/SKILL.md', 'no', 'markdown'),
    ('skills/claude-gemini-team/SKILL.md', '~/.claude/skills/claude-gemini-team/SKILL.md', 'no', 'markdown'),
    ('skills/claude-gemini-team/gemini-tools.md', '~/.claude/skills/claude-gemini-team/gemini-tools.md', 'no', 'markdown'),
]  # เพิ่ม/ลดไฟล์แล้วต้องแก้จำนวนที่ tools/install-agb.ps1 ตรวจ ($blocks.Count) ให้ตรงด้วย


def read(rel):
    with open(os.path.join(ROOT, rel), encoding='utf-8-sig') as f:
        return f.read().rstrip('\r\n').replace('\r\n', '\n')


header = read('tools/header.md')
m = re.search(r'AGB-VERSION:\s*(\S+)', header)
assert m, 'tools/header.md ไม่มี AGB-VERSION'
VERSION = m.group(1)  # แทน {{AGB_VERSION}} ในไฟล์ต้นฉบับ (skill ฝั่ง Gemini ใช้บอกรุ่นของตัวเอง)

out = [header, '',
       '### ตัวติดตั้ง install-agb.ps1 (ขั้นที่ 2 แยกบล็อกนี้ออกมาด้วยคำสั่ง)', '',
       '<!-- AGB-INSTALLER -->',   # header.md ขั้นที่ 2 ใช้ตัวนี้หาบล็อกตัวติดตั้ง
       '````powershell', read('tools/install-agb.ps1'), '````', '']
for src, dst, bom, lang in FILES:
    body = read(src).replace('{{AGB_VERSION}}', VERSION)
    assert '````' not in body, f'{src} มี ```` ซึ่งชนกับตัวคั่นของไฟล์ติดตั้ง'
    out += [f'### {dst}', '', f'<!-- AGB-FILE path="{dst}" bom="{bom}" -->', f'````{lang}', body, '````', '<!-- AGB-END -->', '']
os.makedirs(os.path.join(ROOT, 'dist'), exist_ok=True)
dest = os.path.join(ROOT, 'dist', 'antigravity-bridge-installer.md')
with open(dest, 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(out))
print(f'{dest} · {len(FILES)} ไฟล์')
