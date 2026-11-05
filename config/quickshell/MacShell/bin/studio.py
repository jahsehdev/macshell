#!/usr/bin/env python3
"""Local data bridge for MacShell Calendar, Mail, Photos and Android.

No network inference. Mail imports local archives; Photos edits export copies.
LAN serving is an explicit long-lived command, separate from this request CLI.
"""
import argparse
import datetime as dt
import email.policy
from email.parser import BytesParser
import hashlib
import json
import mailbox
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid
from urllib.parse import unquote, urlparse

DATA=Path(os.environ.get('XDG_DATA_HOME',Path.home()/'.local/share'))/'macshell'
HERE=Path(__file__).resolve().parent

def path_value(value):
    value=str(value)
    return Path(unquote(urlparse(value).path) if value.startswith('file:') else value).expanduser().resolve()

def connect():
    folder=DATA/'studio';folder.mkdir(parents=True,exist_ok=True,mode=0o700)
    conn=sqlite3.connect(folder/'studio.db');conn.row_factory=sqlite3.Row
    os.chmod(folder/'studio.db',0o600)
    conn.executescript('''
    CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,subject TEXT,sender TEXT,recipient TEXT,body TEXT,date TEXT,folder TEXT,updated REAL,raw BLOB);
    CREATE TABLE IF NOT EXISTS photos(id TEXT PRIMARY KEY,path TEXT UNIQUE,title TEXT,album TEXT,updated REAL);
    ''')
    return conn

def imported_message(raw):
    message=BytesParser(policy=email.policy.default).parsebytes(raw)
    part=message.get_body(preferencelist=('plain',)) if message.is_multipart() else message
    body=''
    if part and part.get_content_type()=='text/plain':
        try: body=part.get_content()
        except (LookupError,UnicodeError): body=part.get_payload(decode=True).decode('utf-8','replace')
    if not body: body='[This message has no plain-text body. Remote HTML content is not loaded.]'
    return dict(id=hashlib.sha256(raw).hexdigest(),subject=str(message.get('Subject','(No subject)')),sender=str(message.get('From','')),recipient=str(message.get('To','')),body=body[:1000000],date=str(message.get('Date','')),folder='Inbox',updated=time.time(),raw=raw)

def mail_import(conn,path):
    if not path.is_file() or path.stat().st_size>100*1024*1024: raise ValueError('Choose a local EML/MBOX file smaller than 100 MB.')
    if path.suffix.lower()=='.eml': raws=[path.read_bytes()]
    elif path.suffix.lower() in ('.mbox','.mbx'):
        box=mailbox.mbox(path,create=False)
        try: raws=[box.get_bytes(k) for k in box.iterkeys()]
        finally: box.close()
    else: raise ValueError('Choose an EML or MBOX archive.')
    count=0
    with conn:
        for raw in raws:
            if len(raw)>10*1024*1024: continue
            m=imported_message(raw)
            cursor=conn.execute('INSERT OR IGNORE INTO messages VALUES (:id,:subject,:sender,:recipient,:body,:date,:folder,:updated,:raw)',m)
            count+=cursor.rowcount
    return {'imported':count}

def mail_rows(conn,query=''):
    return [dict(r) for r in conn.execute('SELECT id,subject,sender,recipient,substr(body,1,20000) AS body,date,folder,updated FROM messages WHERE subject LIKE ? OR body LIKE ? ORDER BY updated DESC LIMIT 500',('%'+query+'%','%'+query+'%'))]

def photos_import(conn,folder,album='Library'):
    from PIL import Image
    candidates=[folder] if folder.is_file() else folder.iterdir()
    count=0
    with conn:
        for p in candidates:
            if not p.is_file() or p.suffix.lower() not in ('.jpg','.jpeg','.png','.webp','.bmp','.tiff'): continue
            try:
                with Image.open(p) as image: image.verify()
            except (OSError,ValueError,Image.DecompressionBombError): continue
            resolved=p.resolve();pid=hashlib.sha256(str(resolved).encode()).hexdigest()
            count+=conn.execute('INSERT OR IGNORE INTO photos VALUES(?,?,?,?,?)',(pid,str(resolved),p.name,album[:100],time.time())).rowcount
    return {'imported':count}

def photo_export(conn,pid,destination,operation):
    from PIL import Image,ImageOps
    row=conn.execute('SELECT path FROM photos WHERE id=?',(pid,)).fetchone()
    if not row: raise ValueError('Photo not found.')
    source=Path(row['path']);target=path_value(destination)
    if source==target: raise ValueError('Export to a different file to preserve the original.')
    if target.exists(): raise ValueError('The export file already exists. Choose a new name.')
    with Image.open(source) as original:
        image=ImageOps.exif_transpose(original)
        if operation=='rotate': image=image.rotate(-90,expand=True)
        elif operation=='square':
            size=min(image.size);image=ImageOps.fit(image,(size,size))
        elif operation!='copy': raise ValueError('Unsupported edit.')
        if target.suffix.lower() in ('.jpg','.jpeg'): image=image.convert('RGB')
        # Exclusive reservation: never overwrite another file if it appeared during editing.
        with target.open('xb') as output:
            try: image.save(output,format={'.png':'PNG','.jpg':'JPEG','.jpeg':'JPEG','.webp':'WEBP'}.get(target.suffix.lower(),'PNG'))
            except Exception:
                target.unlink(missing_ok=True);raise
    return {'exported':str(target)}

def calendar_request(action,data):
    if action=='list':
        args=['events','--from',data.get('from',dt.date.today().replace(day=1).isoformat()),'--to',data.get('to',(dt.date.today()+dt.timedelta(days=365)).isoformat())]
    elif action=='parse': args=['parse','--text',data.get('text','')]
    elif action in ('new','save'): args=[action,'--json',json.dumps(data)]
    elif action=='delete':args=['delete','--id',data['id']]
    elif action in ('import','export'):args=[action,'--file',str(path_value(data['path']))]
    else:raise ValueError('Unsupported calendar action.')
    completed=subprocess.run([sys.executable,'-B',str(HERE/'calendar.py'),*args],capture_output=True,text=True,timeout=30)
    return json.loads(completed.stdout)

def rename_suggestion(data):
    path=path_value(data['path'])
    if not path.is_file(): raise ValueError('Choose a local file.')
    # Local deterministic fallback. The model-based name is an editable suggestion in Luma.
    stem=path.stem
    if path.suffix.lower() in ('.txt','.md','.csv','.log'):
        with path.open(errors='replace') as stream:
            for _ in range(30):
                line=stream.readline().strip().lstrip('#').strip()
                if line: stem=line;break
    import re
    stem=re.sub(r'[^\w\s-]','',stem,flags=re.UNICODE).strip()
    stem=re.sub(r'\s+','-',stem)[:70] or 'untitled'
    return {'old':path.name,'suggested':stem+path.suffix,'path':str(path),'method':'local-text-title'}

def rename_file(data):
    source=path_value(data['path']);name=str(data['name']).strip()
    if not source.is_file(): raise ValueError('File not found.')
    if not name or name in ('.','..') or any(c in name for c in ('/','\\','\0')):raise ValueError('Choose a valid filename without path separators.')
    if Path(name).suffix!=source.suffix:raise ValueError('Keep the original file extension.')
    target=source.with_name(name)
    if target==source:return {'renamed':str(source)}
    # Hard-link creation is atomic and refuses an existing destination on this same filesystem.
    os.link(source,target)
    try:source.unlink()
    except Exception:target.unlink(missing_ok=True);raise
    return {'renamed':str(target)}

def request(action,data):
    if action=='files.suggest':return rename_suggestion(data)
    if action=='files.rename':return rename_file(data)
    if action.startswith('calendar.'): return calendar_request(action.split('.',1)[1],data)
    if action=='android.status':
        if not shutil.which('adb') or not shutil.which('scrcpy'):return {'devices':[],'error':'Install adb and scrcpy to connect Android.'}
        result=subprocess.run(['adb','devices'],capture_output=True,text=True,timeout=10)
        if result.returncode:return {'devices':[],'error':result.stderr.strip()[-400:] or 'ADB could not query connected devices.'}
        return {'devices':[{'serial':p[0],'state':p[1]} for line in result.stdout.splitlines()[1:] if len(p:=line.split())>=2]}
    with connect() as conn:
        if action=='mail.list':return {'messages':mail_rows(conn,data.get('query',''))}
        if action=='mail.import':return mail_import(conn,path_value(data['path']))
        if action=='mail.draft':
            mid=data.get('id') or uuid.uuid4().hex
            with conn: conn.execute('INSERT OR REPLACE INTO messages VALUES(?,?,?,?,?,?,?,?,?)',(mid,data.get('subject',''),data.get('sender',''),data.get('recipient',''),data.get('body',''),'', 'Drafts',time.time(),b''))
            return {'id':mid}
        if action=='mail.delete':
            with conn:conn.execute('DELETE FROM messages WHERE id=?',(data['id'],))
            return {'deleted':data['id']}
        if action=='photos.list':return {'photos':[dict(r) for r in conn.execute('SELECT * FROM photos ORDER BY updated DESC LIMIT 2000')]}
        if action=='photos.import':return photos_import(conn,path_value(data['path']),data.get('album','Library'))
        if action=='photos.album':
            with conn:conn.execute('UPDATE photos SET album=? WHERE id=?',(data.get('album','Library')[:100],data['id']))
            return {'updated':True}
        if action=='photos.export':return photo_export(conn,data['id'],data['path'],data.get('operation','copy'))
    raise ValueError('Unknown action.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action');parser.add_argument('--json',default='{}');args=parser.parse_args()
    try: print(json.dumps(request(args.action,json.loads(args.json)),ensure_ascii=False))
    except (OSError,ValueError,KeyError,sqlite3.Error,subprocess.SubprocessError) as exc:print(json.dumps({'error':str(exc)}));sys.exit(1)
