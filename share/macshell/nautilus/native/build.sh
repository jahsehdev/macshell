#!/bin/sh
set -eu
nautilus_native_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
nautilus_native_tmp=$(mktemp "$nautilus_native_dir/.window-controls.XXXXXX.so")
trap 'rm -f -- "$nautilus_native_tmp"' EXIT HUP INT TERM
cc -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$nautilus_native_dir/window-controls.c" \
    $(pkg-config --cflags --libs gtk4 libadwaita-1 json-glib-1.0) \
    -ldl -o "$nautilus_native_tmp"
chmod 755 "$nautilus_native_tmp"
mv -f -- "$nautilus_native_tmp" "$nautilus_native_dir/window-controls.so"
