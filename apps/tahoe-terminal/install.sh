#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install_prefix="${1:-$HOME/.local}"
cmake -S "$project_dir" -B "$project_dir/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$install_prefix"
cmake --build "$project_dir/build" --parallel 2
ctest --test-dir "$project_dir/build" --output-on-failure
cmake --install "$project_dir/build"
if command -v update-desktop-database >/dev/null; then update-desktop-database "$install_prefix/share/applications"; fi
if command -v gtk-update-icon-cache >/dev/null; then gtk-update-icon-cache -f -t "$install_prefix/share/icons/hicolor" >/dev/null 2>&1 || true; fi
printf '\nInstalled Tahoe Terminal in %s\nRun: %s/bin/tahoe-terminal\n' "$install_prefix" "$install_prefix"
