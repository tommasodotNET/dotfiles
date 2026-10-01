#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/share/fnm:$PATH"

if ! command -v fnm >/dev/null 2>&1; then
  installer=$(mktemp)
  trap 'rm -f "$installer"' EXIT
  curl -fsSL https://fnm.vercel.app/install -o "$installer"
  bash "$installer" --install-dir "$HOME/.local/share/fnm" --skip-shell
fi

fnm install 24
fnm default 24
export PATH="$HOME/.local/share/fnm/aliases/default/bin:$PATH"

npm install --global azure-functions-core-tools@4.15.2 --no-audit --no-fund
node --version
npm --version
func --version