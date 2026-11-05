#!/bin/sh
set -eu
controls_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
controls_build=$(mktemp -d "${TMPDIR:-/tmp}/macshell-controls-build.XXXXXX")
controls_gtk_tmp=$(mktemp "$controls_root/gtk3/.controls.XXXXXX.so")
trap 'rm -rf -- "$controls_build"; rm -f -- "$controls_gtk_tmp"' EXIT HUP INT TERM
c++ -std=c++2c -O2 -shared -fPIC -fno-gnu-unique \
    $(pkg-config --cflags hyprland) "$controls_root/spotify-drag.cpp" \
    $(pkg-config --libs hyprland) -o "$controls_build/spotify-drag.so"
install -m755 "$controls_build/spotify-drag.so" "$controls_root/.spotify-drag.new.so"
mv -f "$controls_root/.spotify-drag.new.so" "$controls_root/spotify-drag.so"
c++ $(pkg-config --cflags hyprland) -dM -E -x c++ \
    -include hyprland/src/version.h /dev/null \
    | sed -n 's/^#define GIT_COMMIT_HASH "\(.*\)"$/\1/p' > "$controls_root/spotify-drag.so.commit"
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
