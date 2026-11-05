#!/bin/sh
set -eu
folder_test_source=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
folder_test_binary=$(mktemp /tmp/macshell-folder-menu-test.XXXXXX)
trap 'rm -f -- "$folder_test_binary"' EXIT HUP INT TERM
cc -O0 -g -Wall -Wextra -Werror "$folder_test_source/test-menu.c" \
    $(pkg-config --cflags --libs gtk4 libnautilus-extension-4 json-glib-1.0 gmodule-2.0) \
    -ldl -o "$folder_test_binary"
"$folder_test_binary"
