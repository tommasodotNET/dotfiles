#!/bin/sh
#
# Deliberately apply GNOME-specific dotfiles setup.

set -e

DOTFILES_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

info() {
  printf '\r  [ \033[00;34m..\033[0m ] %s\n' "$1"
}

success() {
  printf '\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n' "$1"
}

link_file() {
  src=$1
  dst=$2

  mkdir -p "$(dirname "$dst")"

  if [ -f "$dst" ] || [ -d "$dst" ] || [ -L "$dst" ]; then
    rm -rf "$dst"
    success "removed $dst"
  fi

  ln -s "$src" "$dst"
  success "linked $src to $dst"
}

install_gnome_symlinks() {
  info 'installing gnome symlinks'

  gnome_extensions_root="$DOTFILES_ROOT/gnome/extensions"

  if [ -d "$gnome_extensions_root" ]; then
    for src in "$gnome_extensions_root"/*; do
      [ -e "$src" ] || continue
      dst="$HOME/.local/share/gnome-shell/extensions/$(basename "$src")"
      link_file "$src" "$dst"
    done
  fi
}

restore_gnome_settings() {
  info 'restoring gnome extension settings'

  shell_dconf="$DOTFILES_ROOT/gnome/shell.dconf"
  extensions_dconf="$DOTFILES_ROOT/gnome/extensions.dconf"

  if [ -f "$shell_dconf" ]; then
    dconf load /org/gnome/shell/ < "$shell_dconf"
    success 'restored gnome shell settings'
  fi

  if [ -f "$extensions_dconf" ]; then
    dconf load /org/gnome/shell/extensions/ < "$extensions_dconf"
    success 'restored gnome extension settings'
  fi
}

install_gnome_symlinks
restore_gnome_settings
"$DOTFILES_ROOT/gnome/setup.sh"