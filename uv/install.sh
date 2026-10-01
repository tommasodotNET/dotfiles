#!/usr/bin/env bash
set -euo pipefail

installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fsSL https://astral.sh/uv/install.sh -o "$installer"
UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$installer"
"$HOME/.local/bin/uv" --version
