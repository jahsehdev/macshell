#!/usr/bin/env python3
"""Capture an explicitly selected screen area and run local OCR only."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def analyze(geometry):
    if not re.fullmatch(r'-?\d+,-?\d+ [1-9]\d*x[1-9]\d*', geometry):
        raise ValueError('Invalid screen selection.')
    if not shutil.which('grim'):
        raise RuntimeError('Screen capture requires grim.')
    directory = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'macshell/visual'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Keep only the most recent temporary captures, never an unbounded screen history.
    for old in sorted(directory.glob('selection-*.png'), key=lambda p:p.stat().st_mtime)[:-3]:
        old.unlink(missing_ok=True)
    fd, filename = tempfile.mkstemp(prefix='selection-', suffix='.png', dir=directory)
    os.close(fd)
    try:
        subprocess.run(['grim','-g',geometry,filename],check=True,capture_output=True,timeout=15)
    except Exception:
        Path(filename).unlink(missing_ok=True)
        raise RuntimeError('Could not capture the selected area.')
    if not shutil.which('tesseract'):
        return {'image':filename, 'text':'', 'error':'Selection captured. Local OCR requires tesseract and language data (eng/ind). No cloud service was contacted.'}
    langs=subprocess.run(['tesseract','--list-langs'],capture_output=True,text=True,timeout=10).stdout.splitlines()
    language='+'.join(x for x in ['eng','ind'] if x in langs)
    if not language:
        return {'image':filename,'text':'','error':'Install English or Indonesian Tesseract language data to read text.'}
    result=subprocess.run(['tesseract',filename,'stdout','-l',language],capture_output=True,text=True,timeout=60)
    if result.returncode:
        return {'image':filename,'text':'','error':'Local OCR failed: '+result.stderr[-300:]}
    return {'image':filename,'text':result.stdout.strip()[:18000], 'error':'', 'capability':'ocr'}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--geometry',required=True)
    args=parser.parse_args()
    try: print(json.dumps(analyze(args.geometry)))
    except (ValueError,RuntimeError,OSError,subprocess.TimeoutExpired) as exc: print(json.dumps({'error':str(exc),'text':''}))
