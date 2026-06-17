#!/bin/sh
#
# Set up Microsoft corporate tooling on Ubuntu LTS:
#   - Microsoft signing keys & repos (prod + insiders-fast + edge)
#   - Microsoft Edge
#   - Visual Studio Code (snap)
#   - Microsoft Identity Broker
#   - Intune Company Portal
#   - linux-entra-sso native connector, when available
#   - Himmelblau stable test stack (without broker)
#   - YubiKey / Smart Card support
#   - Password policy (pam_pwquality)
#   - Microsoft Azure VPN client
#
# Manual follow-up steps after running this script:
#   1. Launch intune-portal and enroll your device
#   2. Install Microsoft Defender for Endpoint via https://aka.ms/yourmsprotect
#   3. Open Edge, sign in with your @microsoft.com account using YubiKey
#   4. Run pam-auth-update and select Himmelblau unlock-only PAM mode
#   5. Run aad-tool auth-test --name <local user>

set -e

HIMMELBLAU_DOMAIN="${DOTFILES_HIMMELBLAU_DOMAIN:-microsoft.com}"
HIMMELBLAU_LOCAL_USER="${DOTFILES_HIMMELBLAU_LOCAL_USER:-${SUDO_USER:-$(id -un)}}"
HIMMELBLAU_UPN="${DOTFILES_HIMMELBLAU_UPN:-tstocchi@${HIMMELBLAU_DOMAIN}}"
HIMMELBLAU_REPO_DISTRO="${DOTFILES_HIMMELBLAU_REPO_DISTRO:-ubuntu26.04}"

os_id() {
  . /etc/os-release
  printf '%s' "$ID"
}

configure_himmelblau_os_override() {
  if [ "$(os_id)" = "ubuntu" ]; then
    return 0
  fi

  echo "  Configuring Himmelblau Ubuntu policy compatibility override…"
  sudo install -d -m 755 /etc/systemd/system/himmelblaud-tasks.service.d

  sudo tee /var/lib/fake-os-release > /dev/null <<'EOF'
PRETTY_NAME="Ubuntu 22.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="22.04"
VERSION="22.04.4 LTS (Jammy Jellyfish)"
VERSION_CODENAME=jammy
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=jammy
EOF

  sudo tee /etc/systemd/system/himmelblaud-tasks.service.d/override.conf > /dev/null <<'EOF'
[Service]
BindReadOnlyPaths=/var/lib/fake-os-release:/usr/lib/os-release
EOF

  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files >/dev/null 2>&1; then
    sudo systemctl daemon-reload
  fi
}

configure_himmelblau() {
  echo "  Configuring Himmelblau for ${HIMMELBLAU_UPN}…"
  sudo install -d -m 755 /etc/himmelblau

  sudo tee /etc/himmelblau/himmelblau.conf > /dev/null <<EOF
[global]
domain = ${HIMMELBLAU_DOMAIN}
enable_experimental_mfa = true
enable_experimental_passwordless_fido = true
apply_policy = true
enable_experimental_intune_custom_compliance = true
hsm_type = tpm
idmap_range = 1000000-1999999
join_type = register
user_map_file = /etc/himmelblau/user-map
# These default options are required on Debian/Ubuntu. See `man himmelblau.conf`
# for an explanation of these parameters. `home_attr` and `home_alias` need to
# match, but don't necessarily need to be set to `CN`.
local_groups = users
home_attr = CN
home_alias = CN
use_etc_skel = true
EOF

  echo "${HIMMELBLAU_LOCAL_USER}:${HIMMELBLAU_UPN}" | sudo tee /etc/himmelblau/user-map > /dev/null
  sudo chmod 600 /etc/himmelblau/user-map

  configure_himmelblau_os_override
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

# ── Himmelblau stable repo ──────────────────────────────────────────────────

echo "  Installing Himmelblau signing key and repo…"
sudo apt upgrade -y
curl -fsSL https://packages.himmelblau-idm.org/himmelblau.asc | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/himmelblau.gpg
echo "deb [arch=amd64] https://packages.himmelblau-idm.org/stable/latest/deb/${HIMMELBLAU_REPO_DISTRO}/ ./" | sudo tee /etc/apt/sources.list.d/himmelblau.list > /dev/null

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

# ── linux-entra-sso native connector ────────────────────────────────────────

echo "  Installing linux-entra-sso native connector, if available…"
if apt-cache show linux-entra-sso >/dev/null 2>&1; then
  sudo apt install -y linux-entra-sso
else
  echo "  linux-entra-sso package not available from configured apt sources; install the native connector manually if needed."
fi

# ── Himmelblau ──────────────────────────────────────────────────────────────

configure_himmelblau

echo "  Installing Himmelblau without broker…"
sudo apt install -y himmelblau pam-himmelblau nss-himmelblau

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files >/dev/null 2>&1; then
  sudo systemctl enable --now himmelblaud himmelblaud-tasks
else
  echo "  systemd is not available; start himmelblaud and himmelblaud-tasks manually after install."
fi

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
echo "    4. Ensure your YubiKey is enrolled as a passkey: https://mysignins.microsoft.com/security-info"
echo "       Also check https://aka.ms/fido2 and https://aka.ms/fido2optin"
echo "    5. Install the linux-entra-sso browser extension for Chrome/Firefox"
echo "    6. Run: sudo pam-auth-update"
echo "       Deselect: Azure Entra Id authentication"
echo "       Select:   Azure Entra Id unlock"
echo "    7. Run: aad-tool auth-test --name ${HIMMELBLAU_LOCAL_USER}"
echo "       Use the same PIN/password as your local user so TPM unlock can happen on login."
echo "    8. Once Himmelblau compliance is confirmed, install himmelblau-broker manually to switch away from intune/identity-broker."
echo ""
