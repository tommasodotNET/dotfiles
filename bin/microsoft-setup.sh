#!/bin/sh
#
# Deliberately apply Microsoft-specific dotfiles setup.

set -e

DOTFILES_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

"$DOTFILES_ROOT/microsoft/setup.sh" "$@"