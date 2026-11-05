#!/usr/bin/env python3
"""Offline-only speech capture/transcription and playback adapters.

STT: whisper.cpp whisper-cli + a user-selected local GGML model.
TTS: espeak-ng. No downloads, accounts, remote inference, or shell evaluation.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

CONFIG=Path(os.environ.get('XDG_CONFIG_HOME',Path.home()/'.config'))/'macshell/voice.json'

def prefs():
    try:return json.loads(CONFIG.read_text())
    except (OSError,ValueError):return {}

def status():
    config=prefs();model=Path(config.get('sttModel','')).expanduser()
    return {'stt':bool(shutil.which('whisper-cli') and shutil.which('pw-record') and model.is_file()),'tts':bool(shutil.which('espeak-ng')),'model':str(model) if model.is_file() else '', 'voice':str(config.get('voice','id')), 'rate':config.get('rate',170)}

def emit(**data):print(json.dumps(data),flush=True)

def parent_death_signal():
    # Linux prctl: child is terminated if the Python bridge is killed by QML Stop.
    ctypes.CDLL(None).prctl(1, signal.SIGTERM)

def record():
    state=status()
    if not state['stt']:emit(event='error',message='Offline dictation needs whisper-cli, pw-record, and a local speech model selected in Luma settings.');return
    recorder=None
    try:
        with tempfile.TemporaryDirectory(prefix='macshell-speech-') as folder:
            audio=Path(folder)/'speech.wav'
            recorder=subprocess.Popen(['pw-record','--rate','16000','--channels','1','--format','s16',str(audio)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,preexec_fn=parent_death_signal)
            emit(event='listening')
            started=time.monotonic()
            while time.monotonic()-started<60 and recorder.poll() is None:
                ready,_,_=select.select([sys.stdin],[],[],0.2)
                if ready:
                    command=sys.stdin.readline().strip()
                    if command in ('stop','cancel',''):
                        if command!='stop':return
                        break
            recorder.send_signal(signal.SIGINT);recorder.wait(timeout=5)
            emit(event='transcribing')
            result=subprocess.run(['whisper-cli','-m',state['model'],'-f',str(audio),'-l',prefs().get('language','auto'),'-nt','-np'],capture_output=True,text=True,timeout=180,preexec_fn=parent_death_signal)
            if result.returncode:raise RuntimeError('Local transcription failed. Verify the speech model and CPU runtime.')
            emit(event='transcript',text=result.stdout.strip()[:3500])
    except (OSError,subprocess.SubprocessError,RuntimeError) as exc:emit(event='error',message=str(exc))
    finally:
        if recorder and recorder.poll() is None:
            recorder.terminate()
            try:recorder.wait(timeout=3)
            except subprocess.TimeoutExpired:recorder.kill();recorder.wait()

def speak(text):
    state=status()
    if not state['tts']:raise RuntimeError('Offline read-aloud requires espeak-ng.')
    subprocess.run(['espeak-ng','-v',state['voice'],'-s',str(max(80,min(300,int(state['rate'])))),'--stdin'],input=text[:18000],text=True,check=True,timeout=180,preexec_fn=parent_death_signal)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['status','configure','record','speak']);parser.add_argument('--model');parser.add_argument('--voice',default='id');parser.add_argument('--rate',type=int,default=170);args=parser.parse_args()
    try:
        if args.action=='status':emit(**status())
        elif args.action=='record':record()
        elif args.action=='speak':speak(sys.stdin.read(18000))
        elif args.action=='configure':
            model=Path(args.model or '').expanduser().resolve()
            if not model.is_file() or model.suffix.lower() not in ('.bin','.ggml'):raise ValueError('Select a local whisper.cpp GGML model (.bin/.ggml).')
            with model.open('rb') as stream:
                if stream.read(4)!=b'lmgg':raise ValueError('This file is not a whisper.cpp GGML model.')
            CONFIG.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
            fd,name=tempfile.mkstemp(dir=CONFIG.parent)
            with os.fdopen(fd,'w') as stream:json.dump({'sttModel':str(model),'voice':args.voice,'rate':max(80,min(300,args.rate)),'language':'auto'},stream)
            os.replace(name,CONFIG);emit(**status())
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as exc:emit(error=str(exc));sys.exit(1)
