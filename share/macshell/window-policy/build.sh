#!/bin/sh
set -eu
policy_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
policy_tmp=$(mktemp "$policy_dir/.window-policy.XXXXXX.so")
trap 'rm -f -- "$policy_tmp"' EXIT HUP INT TERM
c++ -std=c++2c -O2 -Wall -Wextra -shared -fPIC -fno-gnu-unique \
    $(pkg-config --cflags hyprland) "$policy_dir/window-policy.cpp" \
    $(pkg-config --libs hyprland) -o "$policy_tmp"
mv -f -- "$policy_tmp" "$policy_dir/window-policy.so"
c++ $(pkg-config --cflags hyprland) -dM -E -x c++ \
    -include hyprland/src/version.h /dev/null \
    | sed -n 's/^#define GIT_COMMIT_HASH "\(.*\)"$/\1/p' > "$policy_dir/window-policy.so.commit"
