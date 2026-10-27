#!/bin/sh
set -eu
boundary_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
boundary_tmp=$(mktemp "$boundary_dir/.top-boundary.XXXXXX.so")
trap 'rm -f -- "$boundary_tmp"' EXIT HUP INT TERM
c++ -std=c++2c -O2 -shared -fPIC -fno-gnu-unique \
    $(pkg-config --cflags hyprland) "$boundary_dir/top-boundary.cpp" \
    $(pkg-config --libs hyprland) -o "$boundary_tmp"
mv -f -- "$boundary_tmp" "$boundary_dir/top-boundary.so"
