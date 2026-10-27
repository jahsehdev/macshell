#!/bin/sh
set -eu
controls_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
controls_build=$(mktemp -d "${TMPDIR:-/tmp}/macshell-controls-build.XXXXXX")
controls_gtk_tmp=$(mktemp "$controls_root/gtk3/.controls.XXXXXX.so")
trap 'rm -rf -- "$controls_build"; rm -f -- "$controls_gtk_tmp"' EXIT HUP INT TERM
cmake -S "$controls_root/qt" -B "$controls_build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$controls_build" -j2
mkdir -p "$controls_root/qt/plugins/styles"
cp "$controls_build/plugins/styles/libmacshellcontrols.so" "$controls_root/qt/plugins/styles/.libmacshellcontrols.so.new"
chmod 755 "$controls_root/qt/plugins/styles/.libmacshellcontrols.so.new"
mv -f "$controls_root/qt/plugins/styles/.libmacshellcontrols.so.new" "$controls_root/qt/plugins/styles/libmacshellcontrols.so"
cc -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$controls_root/gtk3/controls.c" -o "$controls_gtk_tmp" \
    $(pkg-config --cflags --libs gtk+-3.0)
chmod 755 "$controls_gtk_tmp"
mv -f "$controls_gtk_tmp" "$controls_root/gtk3/controls.so"
