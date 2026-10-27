#!/usr/bin/env bash
set -euo pipefail
bundle_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec python3 "$bundle_root/scripts/install.py" --uninstall "$@"
