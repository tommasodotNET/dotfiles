#!/usr/bin/env bash
# Deliberately not install.sh: generic dotfiles setup must never install a VPN.
set -euo pipefail
exec python3 -B "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/setup.py" "$@"
