"""Apply images/videos transactionally; publish the same media for MacLock/SDDM."""
import argparse
import configparser
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time

HOME = Path.home()
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config'))
CACHE = Path(os.environ.get('XDG_CACHE_HOME', HOME / '.cache')) / 'macshell/wallpaper'
STATE = CONFIG / 'macshell/wallpaper.json'
THEME = HOME / '.local/share/sddm/themes/macshell'
LOGIN = Path('/var/lib/macshell-wallpaper')
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', CACHE)) / 'macshell-wallpaper'
VIDEOS = {'.mp4', '.webm', '.mkv', '.mov', '.m4v'}
IMAGES = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'}


def read_json(path, fallback=None):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {} if fallback is None else fallback


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(value, output, ensure_ascii=False)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def run(args, timeout=30):
    return subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)


def state():
    saved = read_json(STATE)
    if saved.get('path'):
        return saved
    # Migrate existing settings without changing the desktop on a read.
    bar = read_json(CONFIG / 'macbar/settings.json')
    video = bar.get('wallpaperVideo', '')
    still = bar.get('wallpaperPath', '') or bar.get('wpRestorePath', '')
    return dict(mode='live' if video else 'picture', path=video or still, poster=still, preview='')


def prepare(path):
    path = Path(path).expanduser().resolve(strict=True)
    if not path.is_file() or path.suffix.lower() not in VIDEOS | IMAGES:
        raise ValueError('Choose an image or an MP4, WebM, MKV, MOV or M4V video.')
    metadata = path.stat()
    key = hashlib.sha256(f'{path}:{metadata.st_mtime_ns}:{metadata.st_size}'.encode()).hexdigest()[:24]
    CACHE.mkdir(parents=True, exist_ok=True)
    live = path.suffix.lower() in VIDEOS
    poster = CACHE / (key + '.jpg')
    if not poster.is_file():
        # Extract frame zero: seeking to 1s fails on short wallpaper loops.
        result = run(['ffmpeg', '-v', 'error', '-nostdin', '-y', '-i', str(path),
                      '-frames:v', '1', '-vf', 'scale=1920:-2:force_original_aspect_ratio=decrease',
                      '-threads', '1', str(poster)], timeout=60)
        if result.returncode or not poster.is_file() or not poster.stat().st_size:
            poster.unlink(missing_ok=True)
            raise ValueError('Cannot decode this wallpaper. Check the file and ffmpeg codecs.')
    return dict(mode='live' if live else 'picture', path=str(path), poster=str(poster), preview='')


def process_token(pid):
    try:
        text = Path(f'/proc/{pid}/stat').read_text()
        return text[text.rfind(')') + 2:].split()[19]
    except (OSError, IndexError):
        return ''


def alive(record):
    return bool(record.get('token')) and process_token(record['pid']) == record['token']


def stop(records):
    for record in records:
        if alive(record):
            try:
                os.kill(record['pid'], signal.SIGTERM)
            except ProcessLookupError:
                pass
        ipc = record.get('socket')
        if ipc:
            path = Path(ipc)
            if path.parent == RUNTIME:
                path.unlink(missing_ok=True)


def spawn(args, output):
    CACHE.mkdir(parents=True, exist_ok=True)
    with (CACHE / 'player.log').open('ab') as log:
        child = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    record = dict(pid=child.pid, token=process_token(child.pid), output=output)
    return child, record


def monitors():
    try:
        result = run(['hyprctl', '-j', 'monitors'], timeout=5)
        names = [monitor['name'] for monitor in json.loads(result.stdout)]
        return names or ['ALL']
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        return ['ALL']


def apply_video(media, previous, outputs):
    if not shutil.which('mpvpaper'):
        raise ValueError('Live wallpaper needs mpvpaper. Install it with: yay -S mpvpaper')
    children, records = [], []
    try:
        for name in outputs:
            ipc = RUNTIME / (hashlib.sha256(name.encode()).hexdigest()[:12] + f'-{time.time_ns()}.sock')
            options = f'no-config no-audio loop-file=inf hwdec=auto panscan=1 input-ipc-server={ipc}'
            child, record = spawn(['mpvpaper', '-p', '-a', 'FULL', '-o', options, name, media['path']], name)
            record['socket'] = str(ipc)
            children.append(child)
            records.append(record)
        time.sleep(0.45)
        if any(child.poll() is not None for child in children):
            raise ValueError('mpvpaper could not start. See ~/.cache/macshell/wallpaper/player.log.')
    except Exception:
        stop(records)
        raise
    stop(previous)
    # An opaque still-image layer can cover mpvpaper. Stop the old image backends
    # only after the replacement player has survived startup.
    for daemon in ('awww-daemon', 'swww-daemon', 'hyprpaper', 'swaybg'):
        run(['pkill', '-u', str(os.getuid()), '-x', daemon], timeout=5)
    return records


def apply_picture(media, previous, custom=''):
    path = media['path']
    if custom:
        result = run(['sh', '-c', custom.replace('{}', '"$1"'), 'sh', path])
        if result.returncode:
            raise ValueError(result.stderr.strip() or 'The custom wallpaper command failed.')
    else:
        accepted = False
        for client, daemon in (('awww', 'awww-daemon'), ('swww', 'swww-daemon')):
            if not shutil.which(client):
                continue
            if run([client, 'query']).returncode and shutil.which(daemon):
                spawn([daemon], 'static')
                for _ in range(30):
                    if not run([client, 'query']).returncode:
                        break
                    time.sleep(0.1)
            if not run([client, 'img', path, '--transition-type', 'fade', '--transition-duration', '0.7']).returncode:
                accepted = True
                break
        if not accepted and shutil.which('hyprctl'):
            accepted = not run(['hyprctl', 'hyprpaper', 'wallpaper', ',' + path]).returncode
        if not accepted and shutil.which('swaybg'):
            child, record = spawn(['swaybg', '-i', path, '-m', 'fill'], 'static')
            time.sleep(0.2)
            if child.poll() is None:
                stop(previous)
                return [record]
        if not accepted:
            raise ValueError('No image wallpaper backend accepted the file. Install awww or swaybg.')
    stop(previous)
    return []


def copy_atomic(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name('.' + destination.name + '.tmp')
    shutil.copyfile(source, temporary)
    temporary.chmod(0o644)
    temporary.replace(destination)


def publish_login(media):
    """Stage a preview and publish media through SDDM's data-only .user override."""
    folder = THEME / 'assets/wallpaper'
    folder.mkdir(parents=True, exist_ok=True)
    copy_atomic(media['poster'], folder / 'poster.jpg')
    video = ''
    if media['mode'] == 'live':
        video = 'video' + Path(media['path']).suffix.lower()
        copy_atomic(media['path'], folder / video)
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str
    cfg.read(THEME / 'theme.conf')
    if 'General' not in cfg:
        cfg['General'] = {}
    cfg['General']['background'] = 'assets/wallpaper/poster.jpg'
    cfg['General']['backgroundVideo'] = 'assets/wallpaper/' + video if video else ''
    temporary = THEME / '.theme.conf.tmp'
    with temporary.open('w') as output:
        cfg.write(output, space_around_delimiters=False)
    temporary.replace(THEME / 'theme.conf')
    for old in folder.glob('video.*'):
        if old.name != video:
            old.unlink()
    # One administrator installation creates this user-owned public asset
    # directory and a theme.conf.user symlink. Subsequent choices need no sudo.
    if LOGIN.is_dir() and os.access(LOGIN, os.W_OK):
        copy_atomic(media['poster'], LOGIN / 'poster.jpg')
        if video:
            copy_atomic(media['path'], LOGIN / video)
        override = configparser.ConfigParser(interpolation=None)
        override.optionxform = str
        override['General'] = {'background': str(LOGIN / 'poster.jpg'),
                               'backgroundVideo': str(LOGIN / video) if video else ''}
        pending = LOGIN / '.theme.conf.user.tmp'
        with pending.open('w') as output:
            override.write(output, space_around_delimiters=False)
        pending.chmod(0o644)
        pending.replace(LOGIN / 'theme.conf.user')
        for old in LOGIN.glob('video.*'):
            if old.name != video:
                old.unlink()


def apply(path, custom='', restore=False):
    media = prepare(path)
    previous = read_json(RUNTIME / 'players.json', [])
    outputs = monitors() if media['mode'] == 'live' else []
    same_outputs = sorted(p.get('output', '') for p in previous) == sorted(outputs)
    if restore and media['mode'] == 'live' and state().get('path') == media['path'] and same_outputs and previous and all(alive(p) for p in previous):
        current = state()
        current['loginSyncInstalled'] = login_installed()
        return current
    # awww is already displaying the last picture when the shell reloads.
    # Avoid a second fade/copy at the delayed restore after session autostart.
    if restore and media['mode'] == 'picture' and state().get('path') == media['path'] and not previous:
        for client in ('awww', 'swww'):
            if shutil.which(client):
                query = run([client, 'query'])
                if query.returncode == 0 and media['path'] in query.stdout:
                    media['loginSyncInstalled'] = login_installed()
                    return media
    records = apply_video(media, previous, outputs) if media['mode'] == 'live' else apply_picture(media, previous, custom)
    atomic_json(RUNTIME / 'players.json', records)
    atomic_json(STATE, media)
    # Compatibility with older MacShell tools.
    for name in ('wallpaper-video', 'wallpaper-video-play'):
        marker = CONFIG / 'macshell' / name
        if media['mode'] == 'live':
            marker.write_text(media['path'])
        else:
            marker.unlink(missing_ok=True)
    try:
        publish_login(media)
    except OSError as error:
        media['warning'] = f'Wallpaper applied; login screen staging failed: {error}'
    installed = login_installed()
    media['loginSyncInstalled'] = installed
    return media


def pause(output, paused):
    for record in read_json(RUNTIME / 'players.json', []):
        if record.get('output') not in (output, 'ALL') or not record.get('socket') or not alive(record):
            continue
        try:
            with socket.socket(socket.AF_UNIX) as connection:
                connection.settimeout(1)
                connection.connect(record['socket'])
                connection.sendall((json.dumps({'command': ['set_property', 'pause', paused]}) + '\n').encode())
        except OSError:
            pass


def login_installed():
    try:
        override = Path('/usr/share/sddm/themes/macshell/theme.conf.user')
        info = LOGIN.stat()
        return (override.is_symlink() and override.resolve() == LOGIN / 'theme.conf.user'
                and (LOGIN / 'theme.conf.user').is_file() and info.st_uid == os.getuid()
                and bool(info.st_mode & stat.S_IWUSR))
    except OSError:
        return False


def setup_login():
    script = 'bash "$1"; result=$?; printf "\nPress Enter to close…"; read -r answer; exit "$result"'
    command = ['sh', '-c', script, 'sh', str(HOME / '.local/bin/install-macshell-sddm')]
    for terminal, prefix in (('kgx', ['--']), ('foot', ['-e']), ('kitty', []), ('konsole', ['-e']), ('xterm', ['-e'])):
        if shutil.which(terminal):
            subprocess.Popen([terminal] + prefix + command, start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
    raise ValueError('Run ~/.local/bin/install-macshell-sddm in a terminal to enable login sync.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['apply', 'restore', 'state', 'prepare', 'pause', 'publish', 'status', 'setup-login'])
    parser.add_argument('path', nargs='?')
    parser.add_argument('pause_state', nargs='?', choices=['pause', 'resume'])
    parser.add_argument('--command', default='')
    args = parser.parse_args()
    if args.action in ('apply', 'prepare', 'pause') and not args.path:
        parser.error(f'{args.action} requires a file path or output name')
    try:
        if args.action == 'state':
            result = state()
        elif args.action == 'status':
            result = {'loginSyncInstalled': login_installed()}
        elif args.action == 'setup-login':
            setup_login()
            return 0
        elif args.action == 'pause':
            pause(args.path, args.pause_state == 'pause')
            return
        else:
            RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
            with (RUNTIME / 'operation.lock').open('w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                if args.action == 'prepare':
                    result = prepare(args.path)
                elif args.action == 'publish':
                    result = state()
                    if result.get('path'):
                        result = prepare(result['path'])
                        publish_login(result)
                else:
                    current = state()
                    path = current.get('path') if args.action == 'restore' else args.path
                    if not path:
                        return
                    custom = args.command
                    if args.action == 'restore':
                        custom = read_json(CONFIG / 'macbar/settings.json').get('wallpaperCmd', '')
                    result = apply(path, custom, restore=args.action == 'restore')
        print(json.dumps(result, ensure_ascii=False))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({'error': str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
