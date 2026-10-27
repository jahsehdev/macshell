#!/usr/bin/env python3
"""Install official Tabby per user, then switch terminal integrations together."""
import argparse
import base64
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
RELEASE_API = 'https://api.github.com/repos/Eugeny/tabby/releases/latest'


def download(url, target):
    request = urllib.request.Request(url, headers={'User-Agent': 'MacShell-Tabby-Installer', 'Accept': 'application/octet-stream' if '/releases/download/' in url else 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=45) as response, target.open('wb') as output:
        shutil.copyfileobj(response, output)


def package(root):
    cache = root / '.cache/macshell/tabby'
    cache.mkdir(parents=True, exist_ok=True)
    metadata = cache / 'release.json'
    download(RELEASE_API, metadata)
    release = json.loads(metadata.read_text())
    architecture = {'x86_64': 'x64', 'aarch64': 'arm64'}.get(platform.machine())
    if not architecture:
        raise RuntimeError('Unsupported CPU architecture')
    assets = [a for a in release['assets'] if a['name'].endswith(f'linux-{architecture}.deb')]
    if len(assets) != 1:
        raise RuntimeError('Official release has no matching Debian archive')
    asset = assets[0]
    destination = cache / Path(asset['name']).name
    print(f"Downloading official Tabby {release['tag_name']} ({asset['size'] // 1048576} MiB)…", flush=True)
    temporary = destination.with_suffix('.download')
    download(asset['browser_download_url'], temporary)
    digest = asset.get('digest', '')
    if digest.startswith('sha256:'):
        with temporary.open('rb') as source:
            actual = hashlib.file_digest(source, 'sha256').hexdigest()
        if actual != digest.removeprefix('sha256:'):
            temporary.unlink()
            raise RuntimeError('Release checksum mismatch')
    if temporary.stat().st_size != asset['size']:
        raise RuntimeError('Incomplete download')
    temporary.replace(destination)
    return destination


def extract(root, archive):
    if not shutil.which('bsdtar'):
        raise RuntimeError('bsdtar is required to extract the official package')
    versions = root / '.local/share/tabby/versions'
    versions.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='install-', dir=versions))
    try:
        listing = subprocess.check_output(['bsdtar', '-tf', str(archive)], text=True).splitlines()
        member = next((n for n in listing if Path(n).name.startswith('data.tar.')), None)
        if not member:
            raise RuntimeError('Invalid Debian archive')
        data = staging / 'data.tar'
        with data.open('wb') as output:
            subprocess.run(['bsdtar', '-xOf', str(archive), member], stdout=output, check=True)
        subprocess.run(['bsdtar', '--no-same-owner', '--no-same-permissions', '-xf', str(data), '-C', str(staging)], check=True)
        data.unlink()
        binaries = []
        for candidate in staging.rglob('tabby'):
            if candidate.is_file() and not candidate.is_symlink():
                with candidate.open('rb') as source:
                    if source.read(4) == b'\x7fELF':
                        binaries.append(candidate)
        if len(binaries) != 1:
            raise RuntimeError('Cannot locate Tabby executable in official package')
        binary = binaries[0]
        binary.chmod(binary.stat().st_mode | 0o100)
        dependencies = subprocess.run(['ldd', str(binary)], capture_output=True, text=True, check=True)
        if 'not found' in dependencies.stdout:
            raise RuntimeError('Missing application libraries: ' + '; '.join(line.strip() for line in dependencies.stdout.splitlines() if 'not found' in line))
        relative = binary.relative_to(staging)
        target = versions / ('tabby-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
        staging.rename(target)
        return target / relative
    except BaseException:
        if staging.exists():
            shutil.rmtree(staging)
        raise


def terminal_wrapper(root):
    # MacShell and desktop tools use -e; Tabby uses `run [command...]`.
    return '''#!/usr/bin/env python3
import os,sys
from pathlib import Path
target=str(Path.home()/'.local/bin/tabby')
args=sys.argv[1:]
directory=None
while args and args[0] in ('--dir','--working-directory','--workingDirectory'):
    if len(args)<2:raise SystemExit('A working directory is required')
    directory=args[1];args=args[2:]
if directory:os.chdir(directory)
if args[:1] in (['-e'],['--execute'],['--command']):
    args=['run','--',*args[1:]]
elif args[:1]==['--']:
    args=['run','--',*args[1:]]
elif not args:
    args=['open',os.getcwd()]
os.execv(target,[target,*args])
'''


def style(root):
    css = '''/* MacShell: controls occupy the existing Tabby tab row. */
app-root {border:0!important;}
app-root .tab-bar {min-height:38px!important;align-items:center;}
app-root .tab-bar > window-controls {order:-1!important;display:flex!important;
    flex:0 0 66px!important;width:66px!important;gap:6px;align-items:center;
    margin:0 12px!important;background:transparent!important;-webkit-app-region:no-drag;}
app-root .tab-bar > window-controls > button {flex:0 0 18px!important;
    width:18px!important;height:24px!important;min-height:24px!important;
    padding:0!important;border:0!important;border-radius:0!important;
    background-color:transparent!important;background-position:center!important;
    background-repeat:no-repeat!important;background-size:16px 16px!important;
    box-shadow:none!important;-webkit-app-region:no-drag;}
app-root .tab-bar > window-controls > button svg {display:none!important;}
app-root .tab-bar > window-controls > button:nth-child(3) {order:0;}
app-root .tab-bar > window-controls > button:nth-child(1) {order:1;}
app-root .tab-bar > window-controls > button:nth-child(2) {order:2;}
app-root .tab-bar tab-header {font-style:normal!important;}
'''
    for index, kind in [(3, 'close'), (1, 'minimize'), (2, 'maximize')]:
        for pseudo, state in [('', ''), (':hover', '-hover'), (':active', '-active')]:
            path = root / f'.config/macshell/window-controls/dark/titlebutton-{kind}{state}-dark@2.png'
            if path.exists():
                uri = 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()
                css += f'app-root .tab-bar > window-controls > button:nth-child({index}){pseudo} {{background-image:url("{uri}")!important;}}\n'
    return css + Path(__file__).with_name('drag.css').read_text()


def ini_set(text, section, key, value):
    lines = text.splitlines()
    heading = '[' + section + ']'
    start = next((i for i, line in enumerate(lines) if line.strip() == heading), None)
    if start is None:
        return text.rstrip() + f'\n\n{heading}\n{key}={value}\n'
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('[')), len(lines))
    for i in range(start + 1, end):
        if lines[i].startswith(key + '='):
            lines[i] = key + '=' + value
            break
    else:
        lines.insert(end, key + '=' + value)
    return '\n'.join(lines) + '\n'


def prepare_files(root, binary):
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise RuntimeError('Tabby must be installed before changing terminal defaults')
    launcher = root / '.local/bin/macshell-terminal'
    files = {}
    quoted = "'" + str(binary).replace("'", "'\"'\"'") + "'"
    files['.local/bin/tabby'] = f'#!/bin/sh\nexec {quoted} "$@"\n'
    files['.local/bin/macshell-terminal'] = terminal_wrapper(root)
    for name in ['x-terminal-emulator', 'xdg-terminal-exec']:
        files['.local/bin/' + name] = f'#!/bin/sh\nexec "{launcher}" "$@"\n'
    files['.config/xdg-terminals.list'] = 'tabby.desktop\n'
    files['.local/share/applications/tabby.desktop'] = f'''[Desktop Entry]
Type=Application
Name=Tabby
GenericName=Terminal Emulator
Comment=Terminal with integrated macOS window controls
Exec={launcher}
TryExec={root}/.local/bin/tabby
Icon=tabby
Terminal=false
StartupWMClass=tabby
Categories=System;TerminalEmulator;
Keywords=terminal;shell;console;ssh;
X-TerminalArgExec=-e
X-TerminalArgDir=--dir
'''
    config_path = root / '.config/tabby/config.yaml'
    if config_path.exists():
        try:
            config = json.loads(config_path.read_text())
        except ValueError:
            try:
                import yaml
            except ImportError as error:
                raise RuntimeError('Existing Tabby YAML must be preserved; install python-yaml to merge it') from error
            config = yaml.safe_load(config_path.read_text()) or {}
    else:
        config = {'version': 1}
    appearance = config.setdefault('appearance', {})
    appearance.update({'frame': 'thin', 'tabsLocation': 'top'})
    marker = '/* MacShell: controls occupy'
    existing = appearance.get('css', '').split(marker, 1)[0].rstrip()
    appearance['css'] = (existing + '\n' if existing else '') + style(root)
    # JSON is valid YAML and needs no additional package for the first install.
    files['.config/tabby/config.yaml'] = json.dumps(config, indent=2) + '\n'
    plugin = '.config/tabby/plugins/node_modules/tabby-macshell-controls/'
    files[plugin + 'package.json'] = json.dumps({'name': 'tabby-macshell-controls', 'version': '1.0.0',
        'main': 'index.js', 'keywords': ['tabby-plugin'], 'description': 'Integrated native controls for MacShell'}, indent=2) + '\n'
    files[plugin + 'index.js'] = (HERE / 'plugin.js').read_text()
    files[plugin + 'drag.css'] = (HERE / 'drag.css').read_text()
    source = root / '.config/hypr/hyprland.lua'
    if source.exists():
        text = source.read_text()
        text, count = re.subn(r'(local\s+terminal\s*=\s*)["\']kitty["\']', lambda m: m[1] + json.dumps(str(launcher)), text, count=1)
        if not count and 'macshell-terminal' not in text:
            raise RuntimeError('Cannot identify the Hyprland terminal setting')
        files[str(source.relative_to(root))] = text
    source = root / '.config/macbar/settings.json'
    if source.exists():
        data = json.loads(source.read_text()); data['terminal'] = str(launcher)
        files[str(source.relative_to(root))] = json.dumps(data, indent=2) + '\n'
    source = root / '.config/macdock/pinned.json'
    if source.exists():
        pins = json.loads(source.read_text()); pins = ['tabby' if p == 'kitty' else p for p in pins]
        if 'tabby' not in pins: pins.append('tabby')
        files[str(source.relative_to(root))] = json.dumps(list(dict.fromkeys(pins)), indent=2) + '\n'
    for name in ['MacBar.qml', 'MacDock.qml']:
        source = root / '.config/quickshell/MacShell' / name
        if source.exists():
            text = source.read_text()
            if name == 'MacBar.qml':
                text = text.replace('property string terminal: "kitty"', 'property string terminal: ' + json.dumps(str(launcher)))
                text = text.replace('["kitty", "alacritty"', '["tabby", "kitty", "alacritty"')
            else:
                text = text.replace(': "kitty";', ': ' + json.dumps(str(launcher)) + ';')
                text = text.replace('"kitty", "com.mitchellh.ghostty"', '"tabby", "com.mitchellh.ghostty"')
            files[str(source.relative_to(root))] = text
    source = root / '.config/kdeglobals'
    text = source.read_text() if source.exists() else ''
    text = ini_set(text, 'General', 'TerminalApplication', str(launcher))
    files['.config/kdeglobals'] = ini_set(text, 'General', 'TerminalService', 'tabby.desktop')
    source = root / '.local/share/macshell/window-controls/window_action.py'
    if source.exists():
        text = source.read_text()
        if '"tabby":' not in text:
            text = text.replace('CLASSES = {', 'CLASSES = {\n    "tabby": {"tabby", "org.tabby"},', 1)
        files[str(source.relative_to(root))] = text
    return files


def apply(root, files):
    backup = root / '.local/state/macshell/backups' / ('tabby-default-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
    backup.mkdir(parents=True)
    manifest = []
    try:
        for relative, content in files.items():
            destination = root / relative
            record = {'path': relative, 'existed': destination.exists()}
            mode = destination.stat().st_mode & 0o777 if destination.exists() else (0o600 if relative == '.config/tabby/config.yaml' else 0o644)
            if destination.exists():
                saved = backup / relative; saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(destination, saved)
            manifest.append(record)
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + '.tabby-tmp')
            temporary.write_text(content)
            temporary.chmod(0o755 if relative.startswith('.local/bin/') else mode)
            temporary.replace(destination)
    except BaseException:
        for record in reversed(manifest):
            destination = root / record['path']
            if record['existed']: shutil.copy2(backup / record['path'], destination)
            else: destination.unlink(missing_ok=True)
        raise
    (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, help='Use an already downloaded official Tabby .deb')
    args = parser.parse_args()
    root = Path.home()
    try:
        archive = args.package.resolve() if args.package else package(root)
        binary = extract(root, archive)
        files = prepare_files(root, binary)
        backup = apply(root, files)
        versions = root / '.local/share/tabby/versions'
        install_root = next(p for p in binary.parents if p.parent == versions)
        for icon in install_root.rglob('*.png'):
            if icon.name in {'tabby.png', 'icon.png', '512x512.png'}:
                destination = root / '.local/share/icons/hicolor/512x512/apps/tabby.png'
                destination.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(icon, destination); break
        if shutil.which('update-desktop-database'):
            subprocess.run(['update-desktop-database', str(root / '.local/share/applications')], check=False)
        if shutil.which('gsettings'):
            schema = 'org.gnome.desktop.default-applications.terminal'
            schemas = subprocess.run(['gsettings', 'list-schemas'], capture_output=True, text=True).stdout.splitlines()
            if schema in schemas:
                subprocess.run(['gsettings', 'set', schema, 'exec', str(root / '.local/bin/macshell-terminal')], check=False)
                subprocess.run(['gsettings', 'set', schema, 'exec-arg', '-e'], check=False)
        if shutil.which('hyprctl'):
            subprocess.run(['hyprctl', 'reload'], check=False)
        print('Tabby installed. Super+Q, Dock, MacShell menus and desktop terminal defaults now use Tabby.')
        print('Backup:', backup)
        subprocess.Popen([str(root / '.local/bin/macshell-terminal')], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, StopIteration) as error:
        print('Tabby installation could not finish:', error, file=sys.stderr)
        print('Terminal defaults were not switched unless installation and configuration completed.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
