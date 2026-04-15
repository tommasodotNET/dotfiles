#!/bin/sh
#
# Set up Microsoft corporate tooling on Ubuntu LTS:
#   - Microsoft signing keys & repos (prod + insiders-fast + edge)
#   - Microsoft Edge
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
