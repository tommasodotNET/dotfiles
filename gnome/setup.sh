#!/bin/sh
#
# Install GNOME extras. MacTahoe is opt-in; fonts and app fixes remain default.

set -e

DOTFILES_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── GNOME Shell Extensions ─────────────────────────────────────────────────

EXTENSIONS_SOURCE_DIR="$DOTFILES_ROOT/gnome/extensions"
EXTENSIONS_TARGET_DIR="$HOME/.local/share/gnome-shell/extensions"

echo "  Installing bundled GNOME Shell extensions…"
mkdir -p "$EXTENSIONS_TARGET_DIR"
cp -a "$EXTENSIONS_SOURCE_DIR/." "$EXTENSIONS_TARGET_DIR/"
find "$EXTENSIONS_TARGET_DIR" -mindepth 2 -maxdepth 2 -type d -name schemas -exec glib-compile-schemas {} \;

echo "  Loading GNOME Shell configuration…"
dconf load /org/gnome/shell/ < "$DOTFILES_ROOT/gnome/shell.dconf"
dconf load /org/gnome/shell/extensions/ < "$DOTFILES_ROOT/gnome/extensions.dconf"
echo "  GNOME Shell extensions configured. Log out and back in if they do not appear immediately."

# ── CaskaydiaCove Nerd Font Mono ────────────────────────────────────────────

FONT_DIR="$HOME/.local/share/fonts/CaskaydiaCoveNerdFont"

if [ ! -d "$FONT_DIR" ]; then
  echo "  Installing CaskaydiaCove Nerd Font Mono…"
  NERD_FONTS_VERSION=$(curl -sL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
  FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/CascadiaCode.tar.xz"
  mkdir -p "$FONT_DIR"
  curl -sL "$FONT_URL" | tar xJf - -C "$FONT_DIR"
  fc-cache -f "$FONT_DIR"
  echo "  CaskaydiaCove Nerd Font installed."
else
  echo "  CaskaydiaCove Nerd Font already installed, skipping."
fi

# ── Spotify Flatpak Dark Border Fix ─────────────────────────────────────────

SPOTIFY_CONFIG_DIR="$HOME/.var/app/com.spotify.Client/config"
SPOTIFY_FLAGS="$SPOTIFY_CONFIG_DIR/spotify-flags.conf"

if ! flatpak list --app 2>/dev/null | grep -q com.spotify.Client; then
  echo "  Installing Spotify via Flatpak…"
  flatpak install -y flathub com.spotify.Client
fi

echo "  Applying Spotify Flatpak dark border fix…"
mkdir -p "$SPOTIFY_CONFIG_DIR"
cat > "$SPOTIFY_FLAGS" <<'EOF'
--ozone-platform=x11
--enable-features=RunAsNativeGtk
EOF
flatpak override --user --socket=x11 --nosocket=wayland --env=WAYLAND_DISPLAY= com.spotify.Client
echo "  Spotify fix applied."
