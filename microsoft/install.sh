#!/bin/sh
#
# Set up Microsoft corporate tooling on Ubuntu LTS:
#   - Microsoft signing keys & repos (prod + insiders-fast + edge)
#   - Microsoft Edge
#   - Visual Studio Code (snap)
#   - Optional Edge PWA custom icons/launchers from dotfiles
#   - Microsoft Identity Broker
#   - Intune Company Portal
#   - YubiKey / Smart Card support
#   - Password policy (pam_pwquality)
#   - Microsoft Azure VPN client
#
# Manual follow-up steps after running this script:
#   1. Launch intune-portal and enroll your device
#   2. Install Microsoft Defender for Endpoint via https://aka.ms/yourmsprotect
#   3. Open Edge, sign in with your @microsoft.com account using YubiKey

set -e

DOTFILES_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

is_enabled() {
  case "$1" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

INSTALL_MACOS_THEME="${DOTFILES_INSTALL_MACOS_THEME:-${INSTALL_MACOS_THEME:-0}}"
INSTALL_PWA_CUSTOM_ICONS="${DOTFILES_INSTALL_PWA_CUSTOM_ICONS:-${INSTALL_PWA_CUSTOM_ICONS:-0}}"

restore_latest_backup() {
  target=$1
  latest_backup=

  for backup in "${target}.backup-"*; do
    [ -e "$backup" ] || continue
    latest_backup=$backup
  done

  if [ -n "$latest_backup" ] && [ ! -e "$target" ]; then
    mv "$latest_backup" "$target"
    echo "  Restored $target from $latest_backup"
  fi
}

reset_vscode_desktop_icon() {
  code_desktop="$HOME/.local/share/applications/code_code.desktop"
  packaged_code_desktop="/var/lib/snapd/desktop/applications/code_code.desktop"

  [ -f "$code_desktop" ] || return 0

  if ! grep -q "^Icon=$HOME/.local/share/icons/MacTahoe" "$code_desktop"; then
    return 0
  fi

  if [ -f "$packaged_code_desktop" ]; then
    code_icon=$(grep -m 1 '^Icon=' "$packaged_code_desktop" | cut -d= -f2-)
  else
    code_icon=code
  fi

  sed -i "s|^Icon=$HOME/.local/share/icons/MacTahoe.*|Icon=$code_icon|" "$code_desktop"
  echo "  Reset VS Code desktop icon to $code_icon."
}

reset_edge_pwa_hicolor_icons() {
  [ -d "$PWA_TARGET_DIR" ] || return 0
  [ -d "$PWA_DESKTOP_TARGET_DIR" ] || return 0

  for desktop in "$PWA_DESKTOP_TARGET_DIR"/msedge-*.desktop; do
    [ -f "$desktop" ] || [ -L "$desktop" ] || continue

    icon_name=$(grep -m 1 '^Icon=msedge-' "$desktop" | cut -d= -f2-)
    [ -n "$icon_name" ] || continue

    app_id=${icon_name#msedge-}
    app_id=${app_id%-Default}
    icon_dir="$PWA_TARGET_DIR/$app_id/Icons"
    [ -d "$icon_dir" ] || continue

    for icon in "$icon_dir"/*.png; do
      [ -f "$icon" ] || continue
      size=$(basename "$icon" .png)

      case "$size" in
        *[!0-9]*|'') continue ;;
      esac

      hicolor_dir="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
      mkdir -p "$hicolor_dir"
      cp "$icon" "$hicolor_dir/$icon_name.png"
    done
  done
}

cleanup_custom_desktop_icons() {
  reset_vscode_desktop_icon

  if [ -L "$PWA_TARGET_DIR" ] && [ "$(readlink "$PWA_TARGET_DIR")" = "$PWA_DOTFILES_DIR" ]; then
    rm "$PWA_TARGET_DIR"
    echo "  Removed custom Edge PWA manifest resources symlink."
    restore_latest_backup "$PWA_TARGET_DIR"
  fi

  for src in "$PWA_DESKTOP_DOTFILES_DIR"/msedge-*.desktop; do
    [ -e "$src" ] || continue
    dst="$PWA_DESKTOP_TARGET_DIR/$(basename "$src")"

    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      rm "$dst"
      echo "  Removed custom launcher symlink $dst."
      restore_latest_backup "$dst"
    fi
  done

  reset_edge_pwa_hicolor_icons
  refresh_desktop_caches
}

refresh_desktop_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi

  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

# ── Microsoft signing keys & repos ──────────────────────────────────────────

echo "  Installing Microsoft signing keys and repos…"
sudo apt install -y curl gpg

curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc > /dev/null

curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg
sudo install -o root -g root -m 644 /tmp/microsoft.gpg /usr/share/keyrings/microsoft.gpg
rm -f /tmp/microsoft.gpg

# Edge repo
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge-dev.list'

# Microsoft prod repo
sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" >> /etc/apt/sources.list.d/microsoft-ubuntu-$(lsb_release -cs)-prod.list'

# Insiders fast repo (required for latest identity broker / YubiKey support)
sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod insiders-fast main" >> /etc/apt/sources.list.d/microsoft-ubuntu-$(lsb_release -cs)-insiders-fast.list'

sudo apt update

# ── Microsoft Edge ──────────────────────────────────────────────────────────

echo "  Installing Microsoft Edge…"
sudo apt install -y microsoft-edge-stable

# ── Visual Studio Code (snap) ───────────────────────────────────────────────

echo "  Installing Visual Studio Code (snap)…"
if command -v snap >/dev/null 2>&1; then
  if snap list code >/dev/null 2>&1; then
    echo "  VS Code already installed via snap, skipping."
  else
    sudo snap install code --classic
  fi
else
  echo "  snap command not found, skipping VS Code installation."
fi

# ── Optional Edge PWA custom icons and launchers ────────────────────────────

PWA_TARGET_DIR="$HOME/.config/microsoft-edge/Default/Web Applications/Manifest Resources"
PWA_DOTFILES_DIR="$DOTFILES_ROOT/microsoft/edge-pwas"
PWA_DESKTOP_DOTFILES_DIR="$DOTFILES_ROOT/microsoft/edge-pwa-desktop-files"
PWA_DESKTOP_TARGET_DIR="$HOME/.local/share/applications"

if is_enabled "$INSTALL_PWA_CUSTOM_ICONS" && is_enabled "$INSTALL_MACOS_THEME"; then

  # ── Edge PWA manifest resources ───────────────────────────────────────────

  echo "  Linking Edge PWA manifest resources…"
  mkdir -p "$PWA_DOTFILES_DIR"
  mkdir -p "$(dirname "$PWA_TARGET_DIR")"

  if [ ! -L "$PWA_TARGET_DIR" ] && [ -d "$PWA_TARGET_DIR" ] && [ -z "$(ls -A "$PWA_DOTFILES_DIR" 2>/dev/null)" ]; then
    echo "  Seeding dotfiles PWA store from current profile…"
    cp -a "$PWA_TARGET_DIR/." "$PWA_DOTFILES_DIR/"
  fi

  if [ -L "$PWA_TARGET_DIR" ]; then
    echo "  Edge PWA manifest resources already linked, skipping."
  else
    if [ -e "$PWA_TARGET_DIR" ]; then
      BACKUP_PATH="${PWA_TARGET_DIR}.backup-$(date +%Y%m%d%H%M%S)"
      mv "$PWA_TARGET_DIR" "$BACKUP_PATH"
      echo "  Backed up existing PWA manifest resources to $BACKUP_PATH"
    fi
    ln -s "$PWA_DOTFILES_DIR" "$PWA_TARGET_DIR"
    echo "  Linked Edge PWA manifest resources."
  fi

  # ── Edge PWA desktop launchers ────────────────────────────────────────────

  echo "  Linking Edge PWA desktop launchers…"
  mkdir -p "$PWA_DESKTOP_DOTFILES_DIR"
  mkdir -p "$PWA_DESKTOP_TARGET_DIR"

  if [ -z "$(ls -A "$PWA_DESKTOP_DOTFILES_DIR" 2>/dev/null)" ]; then
    echo "  Seeding dotfiles PWA desktop launchers from current profile…"
    for file in "$PWA_DESKTOP_TARGET_DIR"/msedge-*.desktop; do
      [ -e "$file" ] || continue
      cp -a "$file" "$PWA_DESKTOP_DOTFILES_DIR/"
    done
  fi

  for src in "$PWA_DESKTOP_DOTFILES_DIR"/msedge-*.desktop; do
    [ -e "$src" ] || continue
    dst="$PWA_DESKTOP_TARGET_DIR/$(basename "$src")"

    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      continue
    fi

    if [ -L "$dst" ]; then
      rm "$dst"
    elif [ -e "$dst" ]; then
      BACKUP_PATH="${dst}.backup-$(date +%Y%m%d%H%M%S)"
      mv "$dst" "$BACKUP_PATH"
      echo "  Backed up existing launcher to $BACKUP_PATH"
    fi

    ln -s "$src" "$dst"
  done
  echo "  Linked Edge PWA desktop launchers."
elif is_enabled "$INSTALL_PWA_CUSTOM_ICONS"; then
  echo "  Skipping Edge PWA custom icons because DOTFILES_INSTALL_MACOS_THEME is not enabled."
  cleanup_custom_desktop_icons
else
  echo "  Skipping Edge PWA custom icons. Set DOTFILES_INSTALL_PWA_CUSTOM_ICONS=1 with DOTFILES_INSTALL_MACOS_THEME=1 to enable them."
  cleanup_custom_desktop_icons
fi

# ── Microsoft Identity Broker ───────────────────────────────────────────────

echo "  Installing Microsoft Identity Broker…"
sudo apt install -y microsoft-identity-broker

# ── Intune Company Portal ───────────────────────────────────────────────────

echo "  Installing Intune Company Portal…"
sudo apt install -y intune-portal

# ── YubiKey / Smart Card ────────────────────────────────────────────────────

echo "  Setting up YubiKey smart card support…"
sudo apt install -y pcscd yubikey-manager opensc libnss3-tools openssl

mkdir -p "$HOME/.pki/nssdb"
chmod 700 "$HOME/.pki"
chmod 700 "$HOME/.pki/nssdb"
modutil -force -create -dbdir "sql:$HOME/.pki/nssdb"
modutil -force -dbdir "sql:$HOME/.pki/nssdb" -add 'SC Module' -libfile /usr/lib/x86_64-linux-gnu/pkcs11/opensc-pkcs11.so

# ── Password policy (pam_pwquality) ─────────────────────────────────────────

PAM_FILE="/etc/pam.d/common-password"
REQUIRED_LINE="password requisite         pam_pwquality.so retry=3 dcredit=-1 ocredit=-1 ucredit=-1 lcredit=-1 minlen=12"

if grep -q "pam_pwquality.so" "$PAM_FILE"; then
  if ! grep -qF "$REQUIRED_LINE" "$PAM_FILE"; then
    echo "  Updating pam_pwquality password policy…"
    sudo sed -i "s|^password.*pam_pwquality.so.*|${REQUIRED_LINE}|" "$PAM_FILE"
  else
    echo "  Password policy already configured, skipping."
  fi
else
  echo "  Adding pam_pwquality password policy…"
  echo "$REQUIRED_LINE" | sudo tee -a "$PAM_FILE" > /dev/null
fi

# ── Microsoft Azure VPN client ──────────────────────────────────────────────

echo "  Installing Microsoft Azure VPN client…"
curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/prod.list | sudo tee /etc/apt/sources.list.d/microsoft-ubuntu-jammy-prod.list > /dev/null
sudo apt update
sudo apt install -y microsoft-azurevpnclient

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "  Microsoft corporate setup complete."
echo "  Manual steps remaining:"
echo "    1. Run: /usr/bin/intune-portal   — enroll your device"
echo "    2. Install MDE from https://aka.ms/yourmsprotect"
echo "    3. Open Edge, sign in with @microsoft.com using YubiKey"
echo ""
