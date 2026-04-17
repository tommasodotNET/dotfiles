#!/bin/sh
#
# Export current GNOME extension settings to dotfiles.
# Run this whenever you change extension settings and want to persist them.

set -e

DOTFILES_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Exporting GNOME shell settings…"

# Export enabled/disabled extensions and favorite apps
python3 -c "
import sys
lines = sys.stdin.read().split('\n')
in_root = False
for line in lines:
    if line == '[/]':
        in_root = True
        print(line)
        continue
    if in_root:
        if line.startswith('['):
            break
        if line.startswith(('enabled-extensions=', 'disabled-extensions=', 'favorite-apps=')):
            print(line)
" < <(dconf dump /org/gnome/shell/) > "$DOTFILES_ROOT/gnome/shell.dconf"

echo "  ✓ shell.dconf"

# Export extension settings, filtering out machine-specific data
python3 -c "
import sys

skip_sections = {'gsconnect', 'gsconnect/preferences'}
skip_prefixes = ('gsconnect/device/',)
skip_keys = {
    'smart-auto-move': {'saved-windows'},
}

lines = sys.stdin.read().split('\n')
current_section = None
skip = False
result = []

for line in lines:
    if line.startswith('[') and line.endswith(']'):
        section = line[1:-1]
        skip = section in skip_sections or any(section.startswith(p) for p in skip_prefixes)
        current_section = section
        if not skip:
            result.append(line)
    elif not skip:
        key = line.split('=')[0] if '=' in line else ''
        if current_section in skip_keys and key in skip_keys[current_section]:
            continue
        result.append(line)

print('\n'.join(result))
" < <(dconf dump /org/gnome/shell/extensions/) > "$DOTFILES_ROOT/gnome/extensions.dconf"

echo "  ✓ extensions.dconf"

# Copy any new extension directories not yet in dotfiles
SYSTEM_EXT="$HOME/.local/share/gnome-shell/extensions"
DOTFILES_EXT="$DOTFILES_ROOT/gnome/extensions"

if [ -d "$SYSTEM_EXT" ]; then
  for ext in "$SYSTEM_EXT"/*/; do
    ext_name="$(basename "$ext")"
    if [ -L "$SYSTEM_EXT/$ext_name" ]; then
      continue  # already a symlink from dotfiles
    fi
    if [ ! -d "$DOTFILES_EXT/$ext_name" ]; then
      echo "  Copying new extension: $ext_name"
      cp -r "$ext" "$DOTFILES_EXT/$ext_name"
    fi
  done
fi

echo "Done. Review changes with: cd $DOTFILES_ROOT && git diff"
