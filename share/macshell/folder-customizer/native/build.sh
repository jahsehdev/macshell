#!/bin/sh
set -eu
folder_native_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
folder_native_tmp=$(mktemp "$folder_native_dir/.folder-menu.XXXXXX.so")
trap 'rm -f -- "$folder_native_tmp"' EXIT HUP INT TERM
cc -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$folder_native_dir/folder-menu.c" \
    $(pkg-config --cflags --libs gtk4 libnautilus-extension-4 json-glib-1.0 gmodule-2.0) \
    -ldl -o "$folder_native_tmp"
chmod 755 "$folder_native_tmp"
mv -f -- "$folder_native_tmp" "$folder_native_dir/folder-menu.so"
