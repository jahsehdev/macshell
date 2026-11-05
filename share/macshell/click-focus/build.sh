#!/bin/sh
set -eu
focus_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
focus_tmp=$(mktemp "$focus_dir/.click-focus.XXXXXX.so")
trap 'rm -f -- "$focus_tmp"' EXIT HUP INT TERM
c++ -std=c++2c -O2 -shared -fPIC -fno-gnu-unique \
    $(pkg-config --cflags hyprland) "$focus_dir/click-focus.cpp" \
    $(pkg-config --libs hyprland) -o "$focus_tmp"
mv -f -- "$focus_tmp" "$focus_dir/click-focus.so"

# Record the exact compositor commit for safe reload preflight.
c++ $(pkg-config --cflags hyprland) -dM -E -x c++ \
    -include hyprland/src/version.h /dev/null \
    | sed -n 's/^#define GIT_COMMIT_HASH "\(.*\)"$/\1/p' > "$focus_dir/click-focus.so.commit.tmp"
mv -f -- "$focus_dir/click-focus.so.commit.tmp" "$focus_dir/click-focus.so.commit"
