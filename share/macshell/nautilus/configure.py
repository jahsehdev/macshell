#!/usr/bin/env python3
"""Apply MacTahoe GTK4 and route MacShell to Nautilus, with backups."""
from pathlib import Path
import argparse
import configparser
import datetime
import json
import os
import re
import shutil
import subprocess
import sys

HOME = Path.home()
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config'))
DATA = Path(os.environ.get('XDG_DATA_HOME', HOME / '.local/share'))
STATE = Path(os.environ.get('XDG_STATE_HOME', HOME / '.local/state'))
ROOT = DATA / 'macshell/nautilus'
BEGIN, END = '/* BEGIN MacShell MacTahoe */', '/* END MacShell MacTahoe */'
backup = None
manifest = []


def write(path, content):
    global backup
    if path.exists() and not path.is_symlink() and path.read_text() == content:
        return
    if backup is None:
        stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        backup = STATE / 'macshell/backups' / ('nautilus-' + stamp)
        backup.mkdir(parents=True)
    relative = path.relative_to(HOME)
    exists = path.exists() or path.is_symlink()
    manifest.append({'path': str(relative), 'existed': exists})
    if exists:
        target = backup / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target, follow_symlinks=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        path.unlink()
    temporary = path.with_name(path.name + '.macshell-tmp')
    temporary.write_text(content)
    temporary.replace(path)
    (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


def theme_path(variant):
    for directory in [ROOT / 'themes', HOME / '.themes', DATA / 'themes']:
        p = directory / ('MacTahoe-' + variant) / 'gtk-4.0/gtk.css'
        if p.is_file():
            return p
    raise RuntimeError('Missing MacTahoe-' + variant + ' GTK4 assets')


def apply_theme():
    dark = theme_path('Dark')
    light = theme_path('Light')
    is_dark = True
    appearance = CONFIG / 'macbar/settings.json'
    if appearance.exists():
        is_dark = bool(json.loads(appearance.read_text()).get('darkMode', True))
    integration = CONFIG / 'macshell/nautilus'
    write(integration / 'theme-import.css', f'@import url("{(dark if is_dark else light).as_uri()}");\n')
    write(integration / 'dark-import.css', f'@import url("{dark.as_uri()}");\n')
    compatibility = integration / 'compat.css'
    # Map the installed theme's named colors to modern libadwaita variables.
    # Keep MacTahoe styling, with matching heights for Nautilus header controls.
    names = ['window_bg_color', 'window_fg_color', 'view_bg_color', 'view_fg_color',
             'headerbar_bg_color', 'headerbar_fg_color', 'headerbar_border_color',
             'headerbar_backdrop_color', 'headerbar_shade_color', 'sidebar_bg_color',
             'sidebar_fg_color', 'sidebar_backdrop_color', 'sidebar_border_color',
             'sidebar_shade_color', 'card_bg_color', 'card_fg_color', 'card_shade_color',
             'popover_bg_color', 'popover_fg_color', 'popover_shade_color',
             'dialog_bg_color', 'dialog_fg_color', 'accent_bg_color', 'accent_fg_color',
             'accent_color']
    body = '/* MacTahoe colors and Nautilus compatibility adjustments. */\n'
    body += '.nautilus-window {\n'
    body += ''.join(f'  --{name.replace("_", "-")}: @{name};\n' for name in names)
    body += '  background-color: @window_bg_color;\n  color: @window_fg_color;\n}\n'
    body += '.nautilus-window .sidebar-pane { background-color: @sidebar_bg_color; }\n'
    body += '.nautilus-window .sidebar-pane:backdrop { background-color: @sidebar_backdrop_color; }\n'
    body += """/* A GTK popover has one outer transparent node and one rounded panel. */
popover.background, popover.menu {
  background-color: transparent;
  background-image: none;
  border: none;
  border-image: none;
  box-shadow: none;
}
popover > contents {
  background-color: @popover_bg_color;
  background-image: none;
  color: @popover_fg_color;
  border-image: none;
  border: 1px solid alpha(@popover_fg_color, 0.12);
  border-radius: 12px;
  box-shadow: 0 3px 6px alpha(black, 0.15);
}
popover > arrow {
  background-color: @popover_bg_color;
  background-image: none;
  color: @popover_fg_color;
  border-image: none;
  border: 1px solid alpha(@popover_fg_color, 0.12);
}
"""
    body += """/* Keep pathbar containers transparent so the location bar has one capsule. */
.nautilus-window .nautilus-pathbar,
.nautilus-window #NautilusPathBar {
  background-color: transparent;
  background-image: none;
  border: none;
  border-image: none;
  box-shadow: none;
  border-radius: 9999px;
}
.nautilus-window .nautilus-pathbar > scrolledwindow,
.nautilus-window #NautilusPathBar > scrolledwindow {
  background-color: transparent;
  background-image: none;
  border: none;
  border-image: none;
  border-radius: 9999px;
  box-shadow: none;
}
.nautilus-window .nautilus-pathbar > scrolledwindow > viewport,
.nautilus-window #NautilusPathBar > scrolledwindow > viewport {
  background-color: transparent;
  background-image: none;
  border: none;
  border-image: none;
  box-shadow: none;
}
.nautilus-window .nautilus-pathbar > menubutton > button,
.nautilus-window #NautilusPathBar > menubutton > button {
  background-color: transparent;
  background-image: none;
  border: none;
  border-image: none;
  box-shadow: none;
  border-radius: 9999px;
}
.nautilus-window .nautilus-pathbar > menubutton > button:hover,
.nautilus-window .nautilus-pathbar > menubutton > button:checked,
.nautilus-window #NautilusPathBar > menubutton > button:hover,
.nautilus-window #NautilusPathBar > menubutton > button:checked {
  background-color: alpha(@headerbar_fg_color, 0.10);
}
"""
    body += """
/* Give the header controls a consistent 40px outer height. */
.nautilus-window headerbar .nautilus-pathbar,
.nautilus-window headerbar #NautilusPathBar {
  min-height: 40px;
  margin-top: 0;
  margin-bottom: 0;
  padding-top: 0;
  padding-bottom: 0;
}
.nautilus-window headerbar .nautilus-pathbar > scrolledwindow,
.nautilus-window headerbar #NautilusPathBar > scrolledwindow {
  min-height: 40px;
}
.nautilus-window headerbar .nautilus-path-button,
.nautilus-window headerbar #NautilusPathBar #NautilusPathButton {
  min-height: 40px;
  margin: 0;
  padding: 0 10px;
}
.nautilus-window headerbar .nautilus-pathbar > menubutton > button,
.nautilus-window headerbar #NautilusPathBar > menubutton > button,
.nautilus-window headerbar > windowhandle > box > widget > box > button,
.nautilus-window headerbar > windowhandle > box > widget > box > menubutton > button,
.nautilus-window headerbar > windowhandle > box > widget > box > stack > button,
.nautilus-window headerbar > windowhandle > box > widget > box > box > stack > button,
.nautilus-window headerbar > windowhandle > box > widget > box > widget > splitbutton > button,
.nautilus-window headerbar > windowhandle > box > widget > box > widget > splitbutton > menubutton > button {
  min-height: 40px;
  min-width: 40px;
  margin-top: 0;
  margin-bottom: 0;
  padding: 0;
}
/* The history group must not add padding around its 40px buttons. */
.nautilus-window headerbar > windowhandle > box > widget > box.start > stack > widget > box,
.nautilus-window headerbar > windowhandle > box > widget > box.start > box > stack > widget > box {
  margin-top: 0;
  margin-bottom: 0;
  padding: 0;
}
.nautilus-window headerbar > windowhandle > box > widget > box.start > stack > widget > box > button,
.nautilus-window headerbar > windowhandle > box > widget > box.start > box > stack > widget > box > button {
  min-height: 40px;
  min-width: 32px;
  margin-top: 0;
  margin-bottom: 0;
  padding: 0;
}
/* Keep typing a location or searching at the same height as the pathbar. */
.nautilus-window headerbar entry.location-entry,
.nautilus-window headerbar .nautilus-query-editor,
.nautilus-window headerbar #NautilusQueryEditor {
  min-height: 40px;
  margin-top: 0;
  margin-bottom: 0;
  padding-top: 0;
  padding-bottom: 0;
}
"""
    body += """
/* Neutralize menu padding with the same classes used by GTK's menu button. */
.nautilus-window headerbar .nautilus-pathbar {
  padding: 0;
  border-spacing: 6px;
}
.nautilus-window headerbar .nautilus-pathbar > menubutton.flat.popup,
.nautilus-window headerbar .nautilus-pathbar > menubutton.flat.popup > button.toggle {
  min-width: 40px;
  min-height: 40px;
  padding: 0;
  margin: 0;
  border: none;
  border-radius: 9999px;
}
/* Match the outer height of history and view groups to the location bar. */
.nautilus-window headerbar box.start stack > widget > box.horizontal,
.nautilus-window headerbar splitbutton {
  min-height: 40px;
  padding: 0;
  margin-top: 0;
  margin-bottom: 0;
}
.nautilus-window headerbar box.start stack > widget > box.horizontal > button,
.nautilus-window headerbar splitbutton > button.image-button,
.nautilus-window headerbar splitbutton.image-button > button,
.nautilus-window headerbar splitbutton > menubutton.popup > button.toggle,
.nautilus-window headerbar splitbutton.image-button > menubutton.popup > button.toggle:not(.image-button) {
  min-width: 40px;
  min-height: 40px;
  padding: 0;
  margin: 0;
  border: none;
}
.nautilus-window headerbar splitbutton > separator {
  min-width: 1px;
  margin: 8px 0;
}
"""
    body += """
/* Keep Dark's existing geometry in both palette variants. */
.nautilus-window columnview.view > header > button,
.nautilus-window treeview.view > header > button,
.nautilus-window pathbar > button {
  min-height: 26px;
}
window.nautilus-window.csd.ssd-frame headerbar {
  border-top-left-radius: 24px;
  border-top-right-radius: 24px;
}
window.nautilus-window.csd.ssd-frame.maximized headerbar,
window.nautilus-window.csd.ssd-frame.fullscreen headerbar {
  border-top-left-radius: 0;
  border-top-right-radius: 0;
}
"""
    write(compatibility, body)
    for filename, selected in [('gtk.css', 'theme-import.css'), ('gtk-dark.css', 'dark-import.css')]:
        write(CONFIG / 'gtk-4.0' / filename,
              f'@import url("{(integration / selected).as_uri()}");\n'
              f'@import url("{compatibility.as_uri()}");\n')
    settings = CONFIG / 'gtk-4.0/settings.ini'
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if settings.exists(): parser.read(settings)
    if not parser.has_section('Settings'): parser.add_section('Settings')
    parser['Settings']['gtk-theme-name'] = 'MacTahoe-' + ('Dark' if is_dark else 'Light')
    parser['Settings']['gtk-application-prefer-dark-theme'] = '1' if is_dark else '0'
    parser['Settings']['gtk-decoration-layout'] = 'close,minimize,maximize:'
    import io
    buffer = io.StringIO()
    parser.write(buffer, space_around_delimiters=False)
    write(settings, buffer.getvalue())
    print('MacTahoe GTK4: ' + ('Dark' if is_dark else 'Light') + '; native theme geometry; legacy corner overrides disabled for GTK4')


def prepare_integration():
    path = CONFIG / 'hypr/hyprland.lua'
    text = path.read_text()
    text, count = re.subn(r'^local fileManager\s*=\s*[^\n]+', 'local fileManager = "$HOME/.local/bin/macshell-files"', text, count=1, flags=re.M)
    if count != 1:
        raise RuntimeError('Cannot locate Hyprland fileManager declaration')
    write(path, text)
    path = CONFIG / 'quickshell/MacShell/MacDock.qml'
    text = path.read_text()
    start = text.index('        if (item.special === "trash") {')
    finish = text.index('        var wins = windowsFor(item.key);', start)
    text = text[:start] + '''        if (item.special === "trash") {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/macshell-files", "trash:///"]);
            return;
        }
''' + text[finish:]
    # Persisted pin changes from the setup must refresh the live Dock model.
    anchor = '        id: store\n        path: root.configDir + "/pinned.json"'
    replacement = anchor + '\n        watchChanges: true\n        onFileChanged: reload()'
    if anchor in text and replacement not in text:
        text = text.replace(anchor, replacement, 1)
    write(path, text)
    install_native_launcher()


def install_native_launcher():
    launcher = HOME / '.local/bin/macshell-nautilus'
    system_desktop = Path('/usr/share/applications/org.gnome.Nautilus.desktop')
    library = ROOT / 'native/window-controls.so'
    if not launcher.exists() or not library.exists() or not system_desktop.exists():
        return
    desktop = re.sub(r'^Exec=nautilus(?=\s|$)', 'Exec=' + str(launcher), system_desktop.read_text(), flags=re.M)
    write(DATA / 'applications/org.gnome.Nautilus.desktop', desktop)
    write(DATA / 'dbus-1/services/org.gnome.Nautilus.service',
          '[D-BUS Service]\nName=org.gnome.Nautilus\nExec=' + str(launcher) + ' --gapplication-service\n')
    write(DATA / 'dbus-1/services/org.freedesktop.FileManager1.service',
          '[D-BUS Service]\nName=org.freedesktop.FileManager1\nExec=' + str(launcher) + ' --gapplication-service\n')


def gsettings_set(schema, key, value):
    current = subprocess.check_output(['gsettings', 'get', schema, key], text=True).strip()
    snapshots = ROOT / 'previous-gsettings.json'
    saved = json.loads(snapshots.read_text()) if snapshots.exists() else {}
    identifier = schema + ' ' + key
    if identifier not in saved:
        saved[identifier] = current
        write(snapshots, json.dumps(saved, indent=2) + '\n')
    subprocess.run(['gsettings', 'set', schema, key, value], check=True)
    actual = subprocess.check_output(['gsettings', 'get', schema, key], text=True).strip()
    if actual != value:
        raise RuntimeError(f'GSettings did not retain {schema} {key}: {actual}')


def activate():
    if not Path('/usr/bin/nautilus').exists():
        raise RuntimeError('Nautilus is not installed. Run ~/.local/bin/macshell-nautilus-setup in a desktop terminal.')
    # Run with the user's real desktop session; never edit the binary dconf database.
    for schema, key, value in [
        ('org.gnome.nautilus.preferences', 'default-folder-viewer', "'icon-view'"),
        ('org.gnome.nautilus.preferences', 'always-use-location-entry', 'false'),
        ('org.gnome.nautilus.preferences', 'default-sort-order', "'name'"),
        ('org.gnome.nautilus.icon-view', 'default-zoom-level', "'large'"),
        ('org.gnome.desktop.interface', 'icon-theme', "'MacTahoe-dark'"),
        ('org.gnome.desktop.wm.preferences', 'button-layout', "'close,minimize,maximize:'"),
    ]:
        gsettings_set(schema, key, value)
    # Replace the previous Dolphin-specific FileManager1 override.
    install_native_launcher()
    mime = CONFIG / 'mimeapps.list'
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if mime.exists():
        parser.read(mime)
    if not parser.has_section('Default Applications'):
        parser.add_section('Default Applications')
    parser['Default Applications']['inode/directory'] = 'org.gnome.Nautilus.desktop;'
    import io
    buffer = io.StringIO()
    parser.write(buffer, space_around_delimiters=False)
    write(mime, buffer.getvalue())
    pins = CONFIG / 'macdock/pinned.json'
    if pins.exists():
        previous = json.loads(pins.read_text())
        out = []
        for pin in previous:
            value = 'org.gnome.Nautilus' if str(pin).removesuffix('.desktop').lower() == 'org.kde.dolphin' else pin
            if value not in out:
                out.append(value)
        if 'org.gnome.Nautilus' not in out:
            out.insert(1 if out and out[0] == '__launchpad' else 0, 'org.gnome.Nautilus')
        write(pins, json.dumps(out, indent=2) + '\n')
    subprocess.run(['update-desktop-database', str(DATA / 'applications')], check=True)
    print('Nautilus activated: Super+E, Dock, folders and Trash. Existing windows are not terminated.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'theme', 'activate'])
    args = parser.parse_args()
    apply_theme()
    if args.mode != 'theme':
        prepare_integration()
    if args.mode == 'activate':
        activate()
    if backup:
        print('Backup: ' + str(backup))
    if args.mode == 'prepare' and not Path('/usr/bin/nautilus').exists():
        print('Pending system package installation: ~/.local/bin/macshell-nautilus-setup')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print('macshell-nautilus: ' + str(error), file=sys.stderr)
        sys.exit(1)
