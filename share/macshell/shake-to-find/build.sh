#!/bin/sh
set -eu
cursor_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 -B "$cursor_dir/test_symbols.py"
cursor_tmp=$(mktemp "$cursor_dir/.shake-to-find.XXXXXX.so")
trap 'rm -f -- "$cursor_tmp"' EXIT HUP INT TERM
c++ -std=c++2c -O2 -Wall -Wextra -shared -fPIC -fno-gnu-unique \
    $(pkg-config --cflags hyprland) "$cursor_dir/shake-to-find.cpp" \
    $(pkg-config --libs hyprland) -o "$cursor_tmp"
mv -f -- "$cursor_tmp" "$cursor_dir/shake-to-find.so"
c++ $(pkg-config --cflags hyprland) -dM -E -x c++ \
    -include hyprland/src/version.h /dev/null \
    | sed -n 's/^#define GIT_COMMIT_HASH "\(.*\)"$/\1/p' > "$cursor_dir/shake-to-find.so.commit.tmp"
mv -f -- "$cursor_dir/shake-to-find.so.commit.tmp" "$cursor_dir/shake-to-find.so.commit"
