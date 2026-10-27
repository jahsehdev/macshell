#!/bin/sh
set -eu
focus_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
focus_tmp=$(mktemp "$focus_dir/.click-focus.XXXXXX.so")
trap 'rm -f -- "$focus_tmp"' EXIT HUP INT TERM
c++ -std=c++2c -O2 -shared -fPIC -fno-gnu-unique \
    $(pkg-config --cflags hyprland) "$focus_dir/click-focus.cpp" \
    $(pkg-config --libs hyprland) -o "$focus_tmp"
mv -f -- "$focus_tmp" "$focus_dir/click-focus.so"
