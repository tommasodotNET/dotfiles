#!/bin/sh
#
# Install MacTahoe GTK theme, MacTahoe icon theme, and CaskaydiaCove Nerd Font Mono.

set -e

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── MacTahoe GTK Theme ──────────────────────────────────────────────────────

GTK_THEME_DIR="$TMPDIR/MacTahoe-gtk-theme"
git clone https://github.com/vinceliuice/MacTahoe-gtk-theme.git --depth=1 "$GTK_THEME_DIR"

if [ ! -d "$HOME/.themes/MacTahoe-Dark-blue" ]; then
  echo "  Installing MacTahoe GTK theme…"
  cd "$GTK_THEME_DIR"
  ./install.sh -l -c dark -t blue -b
  cd -
else
  echo "  MacTahoe GTK theme already installed, skipping."
fi

# ── MacTahoe GTK Theme Tweaks ───────────────────────────────────────────────

DOTFILES_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "  Applying GDM tweak…"
cd "$GTK_THEME_DIR"
sudo ./tweaks.sh -g -b "$DOTFILES_ROOT/gnome/pictures/starwarshowlpc.jpg"
cd -

echo "  Applying Dash-to-Dock tweak…"
cd "$GTK_THEME_DIR"
./tweaks.sh -d
cd -

echo "  Applying Flatpak theme overrides…"
sudo flatpak override --filesystem=xdg-config/gtk-3.0
sudo flatpak override --filesystem=xdg-config/gtk-4.0
cd "$GTK_THEME_DIR"
./tweaks.sh -F -c dark -t blue
cd -

# ── MacTahoe Icon Theme ─────────────────────────────────────────────────────

if [ ! -d "$HOME/.local/share/icons/MacTahoe-blue" ]; then
  echo "  Installing MacTahoe icon theme…"
  git clone https://github.com/vinceliuice/MacTahoe-icon-theme.git --depth=1 "$TMPDIR/MacTahoe-icon-theme"
  cd "$TMPDIR/MacTahoe-icon-theme"
  ./install.sh -t blue -b
  cd -
else
  echo "  MacTahoe icon theme already installed, skipping."
fi

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
flatpak override --user --nosocket=wayland com.spotify.Client
echo "  Spotify fix applied."
fi
