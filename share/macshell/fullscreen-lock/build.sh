#!/bin/sh
set -eu
lock_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 -B "$lock_dir/test_symbols.py"
lock_tmp=$(mktemp "$lock_dir/.fullscreen-lock.XXXXXX.so")
trap 'rm -f -- "$lock_tmp"' EXIT HUP INT TERM
c++ -std=c++2c -O2 -shared -fPIC -fno-gnu-unique \
    $(pkg-config --cflags hyprland) "$lock_dir/fullscreen-lock.cpp" \
    $(pkg-config --libs hyprland) -o "$lock_tmp"
mv -f -- "$lock_tmp" "$lock_dir/fullscreen-lock.so"
