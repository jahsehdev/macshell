#!/usr/bin/env python3
"""Explicit token-protected photo-album sharing on the local network."""
import argparse
import hashlib
import hmac
import html
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import sqlite3
import subprocess
import sys
from urllib.parse import unquote, urlparse
from PIL import Image

DATA=Path(os.environ.get('XDG_DATA_HOME',Path.home()/'.local/share'))/'macshell'

class AlbumServer(ThreadingHTTPServer):
    daemon_threads=True
    allow_reuse_address=True
    def __init__(self,address,album,token,allow_upload=False):
        self.album=album;self.token=token;self.allow_upload=allow_upload
        super().__init__(address,AlbumHandler)
    def photos(self):
        with sqlite3.connect(DATA/'studio/studio.db') as conn:
            conn.row_factory=sqlite3.Row
            return [dict(r) for r in conn.execute('SELECT * FROM photos WHERE album=?',(self.album,))]

class AlbumHandler(BaseHTTPRequestHandler):
    protocol_version='HTTP/1.0'
    def setup(self):
        super().setup();self.connection.settimeout(10)
    def log_message(self,*args):pass  # Never put token-bearing URLs into logs.
    def reply(self,code,body,mime='text/plain; charset=utf-8'):
        if isinstance(body,str):body=body.encode()
        self.send_response(code);self.send_header('Content-Type',mime)
        self.send_header('Content-Length',str(len(body)));self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff');self.send_header('Referrer-Policy','no-referrer')
        self.send_header('Content-Security-Policy',"default-src 'none'; img-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'")
        self.end_headers();self.wfile.write(body)
    def authorized_path(self):
        ip=ipaddress.ip_address(self.client_address[0])
        if not (ip.is_private or ip.is_loopback):self.reply(403,'Local network access only.');return None
        pieces=urlparse(self.path).path.strip('/').split('/')
        if not pieces or not hmac.compare_digest(pieces[0],self.server.token):self.reply(403,'Invalid or revoked album link.');return None
        return pieces[1:]
    def do_GET(self):
        route=self.authorized_path()
        if route is None:return
        if route and route[0]=='photo' and len(route)==2:
            row=next((p for p in self.server.photos() if p['id']==route[1]),None)
            if not row:self.reply(404,'Photo not found.');return
            try:
                # Re-encode a bounded preview. Never serve arbitrary paths, SVG or HTML.
                with Image.open(row['path']) as image:
                    image.thumbnail((2000,2000));image=image.convert('RGB');out=io.BytesIO();image.save(out,format='JPEG',quality=90)
                self.reply(200,out.getvalue(),'image/jpeg')
            except (OSError,ValueError,Image.DecompressionBombError):self.reply(404,'Preview unavailable.')
            return
        if route:self.reply(404,'Not found.');return
        cards=''.join('<figure><a href="photo/'+p['id']+'"><img loading="lazy" src="photo/'+p['id']+'" alt="'+html.escape(p['title'],quote=True)+'"></a><figcaption>'+html.escape(p['title'])+'</figcaption></figure>' for p in self.server.photos())
        upload='''<label>Add a photo <input id="upload" type="file" accept="image/jpeg,image/png,image/webp"></label><p id="status"></p><script>document.getElementById('upload').onchange=async e=>{let f=e.target.files[0];if(!f)return;let r=await fetch('upload',{method:'POST',body:f});document.getElementById('status').textContent=await r.text();if(r.ok)location.reload();};</script>''' if self.server.allow_upload else '<p>Read-only album</p>'
        self.reply(200,'<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MacShell Shared Album</title><style>body{background:#18181d;color:#f7f7fa;font:16px system-ui;margin:32px}h1{font-size:32px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:20px}figure{margin:0;padding:12px;background:#292930;border-radius:18px}img{width:100%;height:230px;object-fit:contain}figcaption{overflow-wrap:anywhere;margin-top:10px}label{display:block;padding:12px}</style><h1>'+html.escape(self.server.album)+'</h1><p>MacShell Photos · Local network</p>'+upload+'<main>'+cards+'</main></html>','text/html; charset=utf-8')
    def do_POST(self):
        route=self.authorized_path()
        if route is None:return
        if route!=['upload'] or not self.server.allow_upload:self.reply(403,'Uploads are disabled.');return
        try:length=int(self.headers.get('Content-Length','0'))
        except ValueError:self.reply(400,'Invalid length.');return
        if length<=0 or length>20*1024*1024:self.reply(413,'Choose a photo under 20 MB.');return
        raw=self.rfile.read(length)
        if len(raw)!=length:self.reply(400,'Incomplete upload.');return
        try:
            with Image.open(io.BytesIO(raw)) as image:
                image.verify()
                if image.format not in ('JPEG','PNG','WEBP'):raise ValueError('Unsupported image type')
            folder=DATA/'photos/uploads';folder.mkdir(parents=True,exist_ok=True,mode=0o700)
            filename=secrets.token_hex(16)+'.png';target=folder/filename
            with Image.open(io.BytesIO(raw)) as image:image.save(target,format='PNG')
            os.chmod(target,0o600)
            with sqlite3.connect(DATA/'studio/studio.db') as conn:
                import time
                pid=hashlib.sha256(str(target).encode()).hexdigest()
                conn.execute('INSERT INTO photos VALUES(?,?,?,?,?)',(pid,str(target),filename,self.server.album,time.time()))
            self.reply(201,'Photo added.')
        except (OSError,ValueError,Image.DecompressionBombError):self.reply(400,'Invalid image.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--album',required=True);parser.add_argument('--token',default='');parser.add_argument('--allow-upload',action='store_true');args=parser.parse_args()
    token=args.token or secrets.token_urlsafe(32)
    server=AlbumServer(('0.0.0.0',0),args.album,token,args.allow_upload)
    addresses=[]
    try:
        interfaces=json.loads(subprocess.run(['ip','-j','-4','addr'],capture_output=True,text=True,timeout=3).stdout)
        addresses=[a['local'] for iface in interfaces for a in iface.get('addr_info',[]) if a.get('scope')=='global' and ipaddress.ip_address(a['local']).is_private]
    except (OSError,ValueError,KeyError):pass
    host=addresses[0] if addresses else '127.0.0.1'
    print(json.dumps({'url':f'http://{host}:{server.server_port}/{token}/','localOnly':host=='127.0.0.1'}),flush=True)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()
