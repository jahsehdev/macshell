#!/usr/bin/env bash
set -euo pipefail
bundle_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! command -v python3 >/dev/null; then
    echo 'Python 3 diperlukan. Pasang python terlebih dahulu.' >&2
    exit 1
fi
exec python3 "$bundle_root/scripts/install.py" "$@"
