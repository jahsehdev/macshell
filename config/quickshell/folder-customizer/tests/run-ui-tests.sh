#!/usr/bin/env bash
set -euo pipefail
folder_source=$(cd -- "$(dirname -- "$0")/.." && pwd)
folder_test_root=$(mktemp -d /tmp/macshell-folder-ui.XXXXXX)
folder_user_fonts="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
ln -s "$folder_source" "$folder_test_root/Customizer"
ln -s "$folder_source/../MacShell" "$folder_test_root/MacShell"
ln -s "$folder_source/../Common" "$folder_test_root/Common"
# Match root-config implicit loading without any standalone icon type beside the menu.
cp "$folder_source/../MacShell/DesktopMenu.qml" "$folder_test_root/DesktopMenu.qml"
mkdir -p "$folder_test_root/runtime" "$folder_test_root/config/macshell" "$folder_test_root/Recipes" "$folder_test_root/previews"
chmod 700 "$folder_test_root/runtime"
# Keep user-installed fonts available while isolating artwork and settings.
python3 - "$folder_test_root/fonts.conf" "$folder_user_fonts" "${FONTCONFIG_FILE:-/etc/fonts/fonts.conf}" <<'PY'
import sys
import xml.etree.ElementTree as ET
config = ET.Element('fontconfig')
ET.SubElement(config, 'include', ignore_missing='yes').text = sys.argv[3]
ET.SubElement(config, 'dir').text = sys.argv[2]
ET.ElementTree(config).write(sys.argv[1], encoding='utf-8', xml_declaration=True)
PY
export FONTCONFIG_FILE="$folder_test_root/fonts.conf"
export QT_QPA_PLATFORM="${MACSHELL_FOLDER_TEST_PLATFORM:-offscreen}" QT_QUICK_BACKEND="${MACSHELL_FOLDER_TEST_BACKEND:-software}"
export XDG_RUNTIME_DIR="$folder_test_root/runtime" XDG_CONFIG_HOME="$folder_test_root/config" XDG_DATA_HOME="$folder_test_root/data"
export MACSHELL_CUSTOMIZE_FOLDER="$folder_test_root/Recipes" MACSHELL_PREVIEW_DIR="$folder_test_root/previews"
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
export MACSHELL_PREVIEW_ICON=$(python3 - "$folder_source" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + '/bin')
from folder_customizer import artwork
print(artwork(dict(color='#ffd43b', symbol='cutlery')).as_uri())
PY
)
cat > "$folder_test_root/shell.qml" <<'QML'
import Quickshell
import "." as GoldenGate
import "Customizer/tests"
ShellRoot {
    GoldenGate.DesktopMenu { entries: [{ label: "Open", action: "open" }] }
    FolderCustomizerTests {}
    DesktopFolderTests {}
}
QML
set +e
timeout 25 qs -p "$folder_test_root" --no-color > "$folder_test_root/tests.log" 2>&1
folder_test_status=$?
set -e
cat "$folder_test_root/tests.log"
printf 'Test artifacts: %s\n' "$folder_test_root"
[[ $folder_test_status == 0 ]]
rg -q 'TOTALS [1-9][0-9]* passed, 0 failed' "$folder_test_root/tests.log"
if rg -n '(WARN (qml|scene):|ERROR qml:|TypeError|ReferenceError|FAIL!)' "$folder_test_root/tests.log"; then exit 1; fi
