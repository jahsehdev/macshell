#!/usr/bin/env python3
"""Install the complete local MacShell bundle with backups and a file manifest."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = {
    'macbar/settings.json', 'macdock/settings.json', 'macdock/pinned.json',
    'macwidgets/settings.json', 'maclock/settings.json', 'macshell/env',
    'macshell/colors.json', 'macshell/app-menu.json', 'macshell/desktop-dock.json',
    'macshell/icon-style.json', 'macshell/liquidglass.json',
    'quickshell/launchpad/settings.json', 'macshell/corners/state.json',
    'tahoe-terminal/settings.json', 'tahoe-terminal/custom.css', 'MacShell/PhotoBooth.conf',
}
NATIVE = ['top-boundary', 'fullscreen-lock', 'click-focus', 'native-minimize', 'window-controls', 'nautilus/native']


def exists(path):
    return path.exists() or path.is_symlink()


def fingerprint(path):
    if path.is_symlink():
        return 'symlink:' + os.readlink(path)
    return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def paths(args):
    home = Path(args.home or Path.home()).expanduser().absolute()
    config = Path(os.environ.get('XDG_CONFIG_HOME', home / '.config')) if not args.home else home / '.config'
    data = Path(os.environ.get('XDG_DATA_HOME', home / '.local/share')) if not args.home else home / '.local/share'
    state = Path(os.environ.get('XDG_STATE_HOME', home / '.local/state')) if not args.home else home / '.local/state'
    return {'HOME': home, 'CONFIG_HOME': config, 'DATA_HOME': data,
            'PREFIX': home / '.local', 'BIN_DIR': home / '.local/bin', 'STATE_HOME': state}


def rendered(source, target_paths):
    raw = source.read_bytes()
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError:
        return raw
    # Quote template-only shell assignments before inserting paths with spaces.
    if source.suffix == '.sh' or text.startswith(('#!/bin/sh', '#!/usr/bin/env bash', '#!/bin/bash')):
        text = re.sub(r'^(\w+=)(@(?:HOME|CONFIG_HOME|DATA_HOME|BIN_DIR|PREFIX)@[^\s"\']*)$',
                      r'\1"\2"', text, flags=re.M)
    for key, value in target_paths.items():
        text = text.replace('@' + key + '@', str(value))
    return text.encode()


def plan_payload(target_paths, args):
    plan = []
    for source_name, destination in [
        ('config', target_paths['CONFIG_HOME']), ('share', target_paths['DATA_HOME']),
        ('themes', target_paths['DATA_HOME'] / 'themes'), ('icons', target_paths['DATA_HOME'] / 'icons'),
        ('bin', target_paths['BIN_DIR']), ('extras/sddm/theme', target_paths['DATA_HOME'] / 'sddm/themes/macshell'),
    ]:
        source_root = ROOT / source_name
        for source in sorted(source_root.rglob('*')):
            if source.is_dir() and not source.is_symlink():
                continue
            relative = source.relative_to(source_root)
            dest = destination / relative
            preserve = source_name == 'config' and str(relative) in SETTINGS and not args.reset_settings
            plan.append((source, dest, preserve))
    for name in ('install.py', 'dependencies.sh'):
        plan.append((ROOT / 'scripts' / name, target_paths['DATA_HOME'] / 'macshell/installer' / name, False))
    return plan


def command(argv, **kwargs):
    print('+', ' '.join(str(arg) for arg in argv), flush=True)
    subprocess.run([str(arg) for arg in argv], check=True, **kwargs)


def build_apps(staging, target_paths, args):
    staged = []
    for app in ('tahoe-photobooth', 'tahoe-terminal'):
        build = staging / 'build' / app
        command(['cmake', '-S', ROOT / 'apps' / app, '-B', build, '-G', 'Ninja',
                 '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_INSTALL_PREFIX=' + str(target_paths['PREFIX']),
                 '-DBUILD_TESTING=' + ('ON' if args.test else 'OFF')])
        command(['cmake', '--build', build, '--parallel', args.jobs])
        if args.test:
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', QT_STYLE_OVERRIDE='', QT_MEDIA_BACKEND='ffmpeg')
            env.pop('DBUS_SESSION_BUS_ADDRESS', None)
            command(['ctest', '--test-dir', build, '--output-on-failure'], env=env)
        destdir = staging / 'app-install' / app
        command(['cmake', '--install', build], env=dict(os.environ, DESTDIR=str(destdir)))
        for source in sorted(destdir.rglob('*')):
            if source.is_file() or source.is_symlink():
                staged.append((source, Path('/') / source.relative_to(destdir), False))
    native_root = staging / 'native'
    shutil.copytree(ROOT / 'share/macshell', native_root, symlinks=True)
    for part in NATIVE:
        command(['sh', native_root / part / 'build.sh'])
    for source in native_root.rglob('*.so'):
        staged.append((source, target_paths['DATA_HOME'] / 'macshell' / source.relative_to(native_root), False))
    return staged


def restore(record):
    destination = Path(record['path'])
    if exists(destination):
        if destination.is_dir() and not destination.is_symlink():
            raise RuntimeError('Expected file, found directory: ' + str(destination))
        destination.unlink()
    original = record.get('original')
    if original:
        backup = Path(original)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if backup.is_symlink():
            destination.symlink_to(os.readlink(backup))
        else:
            shutil.copy2(backup, destination)


def install(plan, target_paths, args):
    state = target_paths['STATE_HOME'] / 'macshell/installer'
    manifest_path = state / 'manifest.json'
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {'files': []}
    owned = {row['path']: row for row in previous['files']}
    with tempfile.TemporaryDirectory(prefix='macshell-install-') as temporary:
        staging = Path(temporary)
        if not args.skip_build:
            plan.extend(build_apps(staging, target_paths, args))
        stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
        backup = state / 'backups' / stamp
        backup.mkdir(parents=True)
        transaction = []
        result = dict(owned)
        try:
            for source, destination, preserve in plan:
                if preserve and exists(destination):
                    continue
                if destination.is_dir() and not destination.is_symlink():
                    raise RuntimeError('Refusing to replace a directory with a file: ' + str(destination))
                current = fingerprint(destination) if exists(destination) else None
                source_link = os.readlink(source) if source.is_symlink() else None
                content = None if source_link is not None else rendered(source, target_paths)
                desired = 'symlink:' + source_link if source_link is not None else 'sha256:' + hashlib.sha256(content).hexdigest()
                if current == desired:
                    if str(destination) not in result:
                        # Pre-existing identical files belong to the user, not this install.
                        continue
                    continue
                prior_copy = None
                if exists(destination):
                    prior_copy = backup / str(len(transaction))
                    shutil.copy2(destination, prior_copy, follow_symlinks=False)
                transaction.append({'path': str(destination), 'original': str(prior_copy) if prior_copy else None})
                prior_record = owned.get(str(destination))
                original = prior_record.get('original') if prior_record and current == prior_record['installed'] else (str(prior_copy) if prior_copy else None)
                if exists(destination): destination.unlink()
                destination.parent.mkdir(parents=True, exist_ok=True)
                if source_link is not None:
                    destination.symlink_to(source_link)
                else:
                    destination.write_bytes(content)
                    destination.chmod(source.stat().st_mode & 0o777)
                result[str(destination)] = {'path': str(destination), 'installed': desired, 'original': original}
            manifest = {'version': (ROOT / 'VERSION').read_text().strip(), 'source': str(ROOT),
                        'installed_at': stamp, 'files': list(result.values()), 'build_skipped': args.skip_build}
            atomic_json(manifest_path, manifest)
        except BaseException:
            for record in reversed(transaction): restore(record)
            raise
    for command_name, arg in [('update-desktop-database', str(target_paths['PREFIX'] / 'share/applications'))]:
        if shutil.which(command_name):
            subprocess.run([command_name, arg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print('\nMacShell terpasang. Backup dan manifest: ' + str(state))
    print('Masuk kembali ke sesi Hyprland untuk mengaktifkan konfigurasi lengkap.')
    if args.skip_build: print('Build dilewati: aplikasi dan plugin native tidak dibangun; versi yang sudah ada dipertahankan.')


def uninstall(target_paths):
    manifest_path = target_paths['STATE_HOME'] / 'macshell/installer/manifest.json'
    if not manifest_path.exists(): raise RuntimeError('Manifest instalasi tidak ditemukan.')
    manifest = json.loads(manifest_path.read_text())
    skipped = []
    for record in reversed(manifest['files']):
        destination = Path(record['path'])
        if exists(destination) and fingerprint(destination) != record['installed']:
            print('Dipertahankan karena sudah diubah pengguna:', destination)
            skipped.append(record)
            continue
        restore(record)
    if skipped:
        manifest['files'] = skipped
        atomic_json(manifest_path, manifest)
    else:
        manifest_path.unlink()
    print('File instalasi dipulihkan. File yang diubah pengguna tetap dipertahankan.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', help='Home tujuan; untuk staging/pengujian terisolasi')
    parser.add_argument('--no-deps', action='store_true', help='Dependensi sudah dipasang manual')
    parser.add_argument('--skip-build', action='store_true', help='Hanya payload konfigurasi; tidak untuk instalasi lengkap')
    parser.add_argument('--dry-run', action='store_true', help='Tampilkan rencana tanpa menulis atau memasang paket')
    parser.add_argument('--reset-settings', action='store_true', help='Gunakan default paket dan cadangkan preferensi lama')
    parser.add_argument('--uninstall', action='store_true')
    parser.add_argument('--doctor', action='store_true')
    parser.add_argument('--test', action='store_true', help='Build dan jalankan tes aplikasi')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--yes', '-y', action='store_true', help='Mode noninteraktif package manager')
    args = parser.parse_args()
    if args.jobs < 1: parser.error('--jobs harus >= 1')
    target_paths = paths(args)
    if args.uninstall: return uninstall(target_paths)
    if args.doctor:
        return command(['bash', Path(__file__).parent / 'dependencies.sh', '--check'])
    plan = plan_payload(target_paths, args)
    if args.dry_run:
        print('Repo:', ROOT)
        print('Payload:', len(plan), 'file; aplikasi:', 'dilewati' if args.skip_build else 'Photo Booth + Tahoe Terminal + semua plugin native')
        print('Config:', target_paths['CONFIG_HOME'])
        print('Data:', target_paths['DATA_HOME'])
        print('Preferensi lama:', 'dicadangkan dan diganti' if args.reset_settings else 'dipertahankan')
        return
    if os.geteuid() == 0: raise RuntimeError('Jalankan sebagai pengguna biasa, bukan sudo/root.')
    if not args.no_deps:
        command(['bash', ROOT / 'scripts/dependencies.sh', *(['--yes'] if args.yes else [])])
    install(plan, target_paths, args)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        print('macshell-install:', error, file=sys.stderr)
        raise SystemExit(1)
