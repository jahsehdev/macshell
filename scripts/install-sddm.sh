#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
    echo 'Usage: sudo ./scripts/install-sddm.sh /path/to/installed/theme' >&2
    exit 1
fi
source_dir=${1:?Supply the installed MacShell SDDM theme directory}
[[ -f $source_dir/Main.qml && -f $source_dir/theme.conf ]] || { echo 'Theme source is incomplete.' >&2; exit 1; }
backup_dir=$(mktemp -d /var/tmp/macshell-sddm-backup.XXXXXX)
if [[ -d /usr/share/sddm/themes/macshell ]]; then cp -a /usr/share/sddm/themes/macshell "$backup_dir/theme"; fi
if [[ -f /etc/sddm.conf.d/zz-macshell.conf ]]; then cp -a /etc/sddm.conf.d/zz-macshell.conf "$backup_dir/zz-macshell.conf"; fi
install -d /usr/share/sddm/themes /etc/sddm.conf.d
stage=$(mktemp -d /usr/share/sddm/themes/.macshell.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
cp -a "$source_dir/." "$stage/"
chown -R root:root "$stage"
chmod -R a+rX "$stage"
if [[ -d /usr/share/sddm/themes/macshell ]]; then mv /usr/share/sddm/themes/macshell "$backup_dir/previous-theme"; fi
mv "$stage" /usr/share/sddm/themes/macshell
printf '[Theme]\nCurrent=macshell\nThemeDir=/usr/share/sddm/themes\n' > /etc/sddm.conf.d/zz-macshell.conf
printf 'Tema berlaku pada login berikutnya. Cadangan: %s\n' "$backup_dir"
