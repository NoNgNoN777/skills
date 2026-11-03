# -*- coding: utf-8 -*-
r"""รายชื่อแชท Antigravity (อ่านอย่างเดียว) ใช้ให้ผู้ใช้เลือกว่าจะส่งเข้าแชทไหน
  python -I list-chats.py [จำนวน=8]          รายชื่อแชท · แชทที่แอปเปิดค้างอยู่มีป้าย [เปิดอยู่] และขึ้นก่อน
  python -I list-chats.py --transcript <id>  path ของไฟล์ประวัติแชทนั้น (ไว้อ่านความคืบหน้า)
  python -I list-chats.py --projects         รายชื่อโปรเจกต์ (เปิดแชทใหม่ต้องระบุ -Project)
  python -I list-chats.py --diagnose         บอกว่าหาข้อมูลเจอจากไหน (ใช้ตอนแอปอัปเดตแล้วพัง)
ทนต่อการอัปเดตแอป: หาโฟลเดอร์ข้อมูลเอง · หาตารางและคอลัมน์ในฐานข้อมูลจากชื่อ · ถ้าไม่มีฐานข้อมูล
จะไล่จากโฟลเดอร์ brain\ แทน · ตั้ง AGB_GEMINI_DIR เพื่อบังคับตำแหน่งโฟลเดอร์ข้อมูลได้"""
import glob, json, os, re, sqlite3, sys
from datetime import datetime, timezone
from urllib.parse import unquote

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')
HOME = os.path.expanduser('~')
UUID = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')


def data_roots():
    r"""โฟลเดอร์ข้อมูลของ Antigravity: มี brain\ อยู่ข้างใน · antigravity ขึ้นก่อน"""
    forced = os.environ.get('AGB_GEMINI_DIR')
    if forced:
        return [forced]
    roots = [os.path.dirname(b) for b in glob.glob(os.path.join(HOME, '.gemini', '*', 'brain'))]
    roots.sort(key=lambda r: (os.path.basename(r) != 'antigravity', -os.path.getmtime(r)))
    return roots


def find_db(root):
    """ตารางที่มีคอลัมน์ id กับ title คือรายชื่อแชท เลือกคอลัมน์จากชื่อ ไม่ฝังชื่อตายตัว"""
    for db in [os.path.join(root, 'conversation_summaries.db')] + glob.glob(os.path.join(root, '*.db')):
        if not os.path.exists(db):
            continue
        try:
            c = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
            # ข้ามตารางค้นหาข้อความ (fts) ซึ่งมีคอลัมน์ชื่อเดียวกันแต่ 1 แชทมีหลายแถว · ตารางชื่อ summar* ขึ้นก่อน
            tables = [t for (t, sql) in c.execute("select name, sql from sqlite_master where type='table'")
                      if 'fts' not in t.lower() and 'virtual table' not in (sql or '').lower()]
            tables.sort(key=lambda t: 'summar' not in t.lower())
            for t in tables:
                cols = [r[1] for r in c.execute(f'pragma table_info("{t}")')]
                pick = lambda *keys: next((x for k in keys for x in cols if k in x.lower()), None)
                cid, title, prev = pick('conversation_id', 'conv_id'), pick('title'), pick('preview', 'summary')
                if cid and (title or prev):
                    return c, t, dict(id=cid, title=title, prev=prev, time=pick('last_modified', 'modified', 'updated', 'time'),
                                      ws=pick('workspace'), steps=pick('step_count', 'steps')), db
        except sqlite3.Error:
            pass
    return None


def is_open(root, cid):
    # แอปล็อกไฟล์ presence\<id>.lock ไว้ระหว่างแชทเปิด อ่านไม่ได้ = เปิดอยู่ · ไม่มีโฟลเดอร์นี้ = บอกไม่ได้ (None)
    pdir = os.path.join(root, 'presence')
    if not os.path.isdir(pdir):
        return None
    p = os.path.join(pdir, f'{cid}.lock')
    if not os.path.exists(p):
        return False
    try:
        with open(p, 'rb') as f:
            f.read(1)
        return False
    except OSError:
        return True


def transcript_files(root, cid):
    r"""ไฟล์ประวัติแชท เรียงเก่า→ใหม่: แบบไฟล์เดียว transcript.jsonl หรือแบบแบ่ง chunks\transcript\NNNNNNNN.jsonl"""
    base = os.path.join(root, 'brain', cid)
    # ตำแหน่งที่รู้จักก่อน (เร็ว) แชทยาวมีไฟล์รูปเป็นพัน การไล่ทั้งโฟลเดอร์ช้า
    logs = os.path.join(base, '.system_generated', 'logs')
    if os.path.isfile(os.path.join(logs, 'transcript.jsonl')):
        return [os.path.join(logs, 'transcript.jsonl')]
    cdir = os.path.join(logs, 'chunks', 'transcript')
    if os.path.isdir(cdir):
        return sorted(os.path.join(cdir, f) for f in os.listdir(cdir) if f.endswith('.jsonl'))
    # ไม่เจอที่เดิม (แอปอาจย้ายที่): glob ข้ามโฟลเดอร์ที่ขึ้นต้นด้วยจุด จึงไล่ด้วย os.walk
    single, chunks = [], []
    for d, _, files in os.walk(base):
        if 'transcript.jsonl' in files:
            single.append(os.path.join(d, 'transcript.jsonl'))
        if os.path.basename(d) == 'transcript' and os.path.basename(os.path.dirname(d)) == 'chunks':
            chunks += [os.path.join(d, f) for f in files if f.endswith('.jsonl')]
    return single[:1] if single else sorted(chunks)


def transcript(root, cid):
    files = transcript_files(root, cid)
    return files[-1] if files else None   # ไฟล์ล่าสุด = ที่มีความคืบหน้าล่าสุด


def first_user_text(root, cid):
    files = transcript_files(root, cid)
    try:
        with open(files[0], encoding='utf-8') as f:
            for line in f:
                r = json.loads(line)
                if str(r.get('source', '')).upper().startswith('USER') and r.get('content'):
                    m = re.search(r'<USER_REQUEST>\s*(.*?)\s*</USER_REQUEST>', str(r['content']), re.S)
                    return ' '.join((m.group(1) if m else str(r['content'])).split())[:50]
    except (OSError, ValueError, IndexError):
        pass
    return None


def open_ids(root):
    """id ของแชทที่แอปเปิดค้างอยู่ทั้งหมด (ไฟล์ .lock ที่อ่านไม่ได้) · ไว้ดึงขึ้นมาแม้อยู่นอก n แชทล่าสุด"""
    pdir = os.path.join(root, 'presence')
    if not os.path.isdir(pdir):
        return []
    ids = [f[:-5] for f in os.listdir(pdir) if f.endswith('.lock') and UUID.match(f[:-5])]
    return [i for i in ids if is_open(root, i)]


def rows_from_db(found, n, extra=()):
    c, t, col, _ = found
    sel = ', '.join(f'"{col[k]}"' if col[k] else 'null' for k in ('id', 'title', 'prev', 'time', 'ws', 'steps'))
    order = f'order by "{col["time"]}" desc' if col['time'] else ''
    rows = list(c.execute(f'select {sel} from "{t}" {order} limit ?', (n,)))
    got = {r[0] for r in rows}
    for cid in extra:
        if cid not in got:
            rows += list(c.execute(f'select {sel} from "{t}" where "{col["id"]}" = ?', (cid,)))
    for cid, title, prev, mod, ws, steps in rows:
        # แชทส่วนใหญ่ title ว่าง แต่มีชื่อใน preview
        title = title or (' '.join(str(prev).split())[:60] if prev else None)
        try:
            ws = ', '.join(unquote(os.path.basename(u.rstrip('/'))) for u in json.loads(ws)) if ws else ''
        except (ValueError, TypeError):
            ws = unquote(str(ws or ''))
        yield cid, title, str(mod or '')[:16], ws, steps


def rows_from_brain(root, n, extra=()):
    dirs = [d for d in glob.glob(os.path.join(root, 'brain', '*')) if UUID.match(os.path.basename(d))]
    dirs = sorted(dirs, key=os.path.getmtime, reverse=True)[:n]
    dirs += [os.path.join(root, 'brain', i) for i in extra
             if os.path.isdir(os.path.join(root, 'brain', i)) and os.path.join(root, 'brain', i) not in dirs]
    for d in dirs:
        cid = os.path.basename(d)
        mod = datetime.fromtimestamp(os.path.getmtime(d), timezone.utc).strftime('%Y-%m-%d %H:%M')
        yield cid, first_user_text(root, cid), mod, '', ''


def main():
    args = sys.argv[1:]
    roots = data_roots()
    if not roots:
        sys.exit('ไม่พบโฟลเดอร์ข้อมูลของ Antigravity (หา ~/.gemini/*/brain ไม่เจอ) · ตั้ง AGB_GEMINI_DIR หรือรัน doctor.ps1')
    root = roots[0]
    if args[:1] == ['--transcript']:
        p = transcript(root, args[1]) if len(args) > 1 else None
        sys.exit(print(p) if p else 'ไม่พบ transcript ของแชทนี้')
    if args[:1] == ['--projects']:
        # โปรเจกต์ใน ~/.gemini/*/projects/*.json (เปิดแชทใหม่ต้องระบุ) เรียงตามที่แก้ล่าสุด
        files = glob.glob(os.path.join(HOME, '.gemini', '*', 'projects', '*.json'))
        for f in sorted(files, key=os.path.getmtime, reverse=True):
            try:
                j = json.load(open(f, encoding='utf-8'))
            except (OSError, ValueError):
                continue
            res = (j.get('projectResources') or {}).get('resources') or []
            folders = ', '.join(re.sub(r'^file:/*', '', unquote(str(r['folderUri']))) for r in res if r.get('folderUri'))
            print(f'{j.get("id")} | {unquote(str(j.get("name", "")))} | {folders}')
        return
    found = find_db(root)
    if args[:1] == ['--diagnose']:
        print('data_root:', root)
        print('database :', f'{found[3]} ตาราง {found[1]} คอลัมน์ {found[2]}' if found else 'ไม่พบ (ใช้การไล่โฟลเดอร์ brain แทน ชื่อแชทจะเป็นข้อความแรกของผู้ใช้)')
        print('presence :', 'มี' if os.path.isdir(os.path.join(root, 'presence')) else 'ไม่มี (บอกไม่ได้ว่าแชทไหนเปิดอยู่)')
        return
    if args and not args[0].isdigit():
        sys.exit(__doc__)
    n = int(args[0]) if args else 8
    extra = open_ids(root)
    rows = list(rows_from_db(found, n, extra) if found else rows_from_brain(root, n, extra))
    out = []
    for cid, title, mod, ws, steps in rows:
        st = is_open(root, cid)
        tag = '[เปิดอยู่] ' if st else ''
        out.append((not st, f'{tag}{cid} | {title or "(ไม่มีชื่อ)"} | {ws} | {mod} | {steps} steps'))
    for _, line in sorted(out, key=lambda x: x[0]):
        print(line)
    if not found:
        print('(หมายเหตุ: ไม่พบฐานข้อมูลรายชื่อแชท ใช้การไล่โฟลเดอร์แทน)')


main()
