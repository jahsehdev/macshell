"""Real local-store flows: mail import/drafts, image exports and enabled context."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from PIL import Image

HERE=Path(__file__).resolve().parents[1]/'bin'

class StudioFlows(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name)
        self.env=dict(os.environ,XDG_DATA_HOME=str(self.base/'data'))
    def call(self,action,data=None):
        result=subprocess.run([sys.executable,'-B',str(HERE/'studio.py'),action,'--json',json.dumps(data or {})],env=self.env,capture_output=True,text=True,timeout=10)
        return json.loads(result.stdout)
    def ctx(self,*args):
        result=subprocess.run([sys.executable,'-B',str(HERE/'context.py'),*args],env=self.env,capture_output=True,text=True,timeout=15)
        return json.loads(result.stdout)
    def test_mail_import_deduplicates_and_preserves_plain_text(self):
        path=self.base/'message.eml';path.write_text('From: person@example.test\nTo: me@example.test\nSubject: Meeting Jakarta\nContent-Type: text/plain; charset=utf-8\n\nMeet at ten tomorrow.\n')
        self.assertEqual(self.call('mail.import',{'path':str(path)})['imported'],1)
        self.assertEqual(self.call('mail.import',{'path':str(path)})['imported'],0)
        row=self.call('mail.list')['messages'][0]
        self.assertEqual(row['subject'],'Meeting Jakarta');self.assertIn('ten tomorrow',row['body'])
    def test_mail_html_is_not_rendered_or_fetched(self):
        path=self.base/'html.eml';path.write_text('Subject: Remote\nContent-Type: text/html\n\n<img src="https://tracker.invalid/pixel">')
        self.call('mail.import',{'path':str(path)})
        self.assertIn('no plain-text body',self.call('mail.list')['messages'][0]['body'])
    def test_draft_roundtrip_and_delete(self):
        draft=self.call('mail.draft',{'subject':'Draft','body':'Local only','recipient':'test@example.test'})
        self.assertTrue(draft['id']);self.assertEqual(self.call('mail.list')['messages'][0]['folder'],'Drafts')
        self.call('mail.delete',draft);self.assertEqual(self.call('mail.list')['messages'],[])
    def test_mail_context_excludes_disabled_source(self):
        self.call('mail.draft',{'subject':'Orchid','body':'Appointment at ten'})
        self.ctx('enable','--kind','mail');report=self.ctx('index')
        self.assertEqual(report['report']['mail']['indexed'],1)
        self.assertEqual(len(self.ctx('search','--query','Orchid')['results']),1)
        self.ctx('disable','--kind','mail')
        self.assertEqual(self.ctx('search','--query','Orchid')['results'],[])
    def test_photo_edit_exports_without_overwriting_original_or_existing_file(self):
        source=self.base/'source.png';Image.new('RGB',(80,40),'red').save(source);original=source.read_bytes()
        self.call('photos.import',{'path':str(source)})
        row=self.call('photos.list')['photos'][0]
        output=self.base/'rotated.png'
        self.call('photos.export',{'id':row['id'],'path':str(output),'operation':'rotate'})
        with Image.open(output) as edited:self.assertEqual(edited.size,(40,80))
        self.assertEqual(source.read_bytes(),original)
        self.assertIn('error',self.call('photos.export',{'id':row['id'],'path':str(source)}))
        self.assertIn('error',self.call('photos.export',{'id':row['id'],'path':str(output)}))
    def test_calendar_creates_lists_and_removes_real_event(self):
        event=self.call('calendar.new',{'title':'Local calendar','start':'2026-11-02T10:00:00+07:00','end':'2026-11-02T11:00:00+07:00','reminders':[0]})['event']
        rows=self.call('calendar.list',{'from':'2026-11-01','to':'2026-11-30'})['events']
        self.assertEqual(rows[0]['id'],event['id']);self.call('calendar.delete',{'id':event['id']})
        self.assertEqual(self.call('calendar.list',{'from':'2026-11-01','to':'2026-11-30'})['events'],[])
    def test_rename_never_overwrites_and_preserves_extension(self):
        source=self.base/'report.txt';source.write_text('Project Orchid\nSome text')
        suggestion=self.call('files.suggest',{'path':str(source)})
        self.assertEqual(suggestion['suggested'],'Project-Orchid.txt')
        existing=self.base/'exists.txt';existing.write_text('Keep this')
        self.assertIn('error',self.call('files.rename',{'path':str(source),'name':'exists.txt'}))
        self.assertEqual(existing.read_text(),'Keep this');self.assertTrue(source.exists())
        self.assertIn('error',self.call('files.rename',{'path':str(source),'name':'../outside.txt'}))
        self.assertIn('error',self.call('files.rename',{'path':str(source),'name':'changed.png'}))
        self.assertIn('renamed',self.call('files.rename',{'path':str(source),'name':suggestion['suggested']}))
        self.assertFalse(source.exists())

    def test_lan_rejects_bad_token_and_unknown_photo_id(self):
        import io,types
        spec=importlib.util.spec_from_file_location('album',HERE/'album_lan.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        handler=module.AlbumHandler.__new__(module.AlbumHandler)
        handler.server=types.SimpleNamespace(token='secret-token',photos=lambda:[],album='Test',allow_upload=False)
        handler.client_address=('127.0.0.1',12345)
        replies=[];handler.reply=lambda *args:replies.append(args)
        handler.path='/bad-token/'
        handler.do_GET();self.assertEqual(replies[-1][0],403)
        handler.path='/secret-token/photo/../../etc/passwd'
        handler.do_GET();self.assertEqual(replies[-1][0],404)
        handler.path='/secret-token/upload'
        handler.do_POST();self.assertEqual(replies[-1][0],403)
        handler.path='/secret-token/'
        handler.do_GET();self.assertEqual(replies[-1][0],200)

    def test_visual_geometry_rejects_shell_or_path_injection(self):
        spec=importlib.util.spec_from_file_location('visual',HERE/'visual_intelligence.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        for value in ['0,0 0x20','0,0 1x1; touch /tmp/x','../secret']:
            with self.assertRaises(ValueError):module.analyze(value)

if __name__=='__main__':unittest.main()
