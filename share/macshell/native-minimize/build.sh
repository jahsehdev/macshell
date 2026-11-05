#!/bin/sh
set -eu
bridge_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bridge_tmp=$(mktemp "$bridge_dir/.native-minimize.XXXXXX.so")
trap 'rm -f -- "$bridge_tmp"' EXIT HUP INT TERM
c++ -std=c++2c -O2 -shared -fPIC -fno-gnu-unique \
    $(pkg-config --cflags hyprland) "$bridge_dir/native-minimize.cpp" \
    $(pkg-config --libs hyprland) -o "$bridge_tmp"
mv -f -- "$bridge_tmp" "$bridge_dir/native-minimize.so"

# Record the exact compositor commit for safe reload preflight.
c++ $(pkg-config --cflags hyprland) -dM -E -x c++ \
    -include hyprland/src/version.h /dev/null \
    | sed -n 's/^#define GIT_COMMIT_HASH "\(.*\)"$/\1/p' > "$bridge_dir/native-minimize.so.commit.tmp"
mv -f -- "$bridge_dir/native-minimize.so.commit.tmp" "$bridge_dir/native-minimize.so.commit"
