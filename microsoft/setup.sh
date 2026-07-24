#!/bin/sh
#
# Set up Microsoft corporate tooling on Fedora:
#   - Microsoft signing keys & RPM repos (prod + edge + VS Code)
#   - Microsoft Edge
#   - Visual Studio Code
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
#   4. Review authselect/PAM before enabling interactive Entra login
#   5. Run aad-tool auth-test --name <local user>

set -e

HIMMELBLAU_DOMAIN="${DOTFILES_HIMMELBLAU_DOMAIN:-microsoft.com}"
HIMMELBLAU_LOCAL_USER="${DOTFILES_HIMMELBLAU_LOCAL_USER:-${SUDO_USER:-$(id -un)}}"
HIMMELBLAU_UPN="${DOTFILES_HIMMELBLAU_UPN:-tstocchi@${HIMMELBLAU_DOMAIN}}"
HIMMELBLAU_REPO_DISTRO="${DOTFILES_HIMMELBLAU_REPO_DISTRO:-ubuntu24.04}"

os_id() {
  . /etc/os-release
  printf '%s' "$ID"
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
# These default options keep local home-directory mapping predictable. See `man himmelblau.conf`
# for an explanation of these parameters. `home_attr` and `home_alias` need to
# match, but don't necessarily need to be set to `CN`.
local_groups = users
home_attr = CN
home_alias = CN
use_etc_skel = true
EOF

  echo "${HIMMELBLAU_LOCAL_USER}:${HIMMELBLAU_UPN}" | sudo tee /etc/himmelblau/user-map > /dev/null
  sudo chmod 600 /etc/himmelblau/user-map

}

# ── Package helpers ────────────────────────────────────────────────────────

install_if_available() {
  package=$1

  if sudo dnf list --available "$package" >/dev/null 2>&1 || rpm -q "$package" >/dev/null 2>&1; then
    sudo dnf install -y "$package"
  else
    echo "  $package package not available from configured dnf repos; install it manually if needed."
  fi
}

# ── Microsoft signing keys & repos ──────────────────────────────────────────

echo "  Installing Microsoft signing keys and repos…"
sudo dnf install -y curl ca-certificates gnupg2 dnf-plugins-core
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

# Edge repo
sudo tee /etc/yum.repos.d/microsoft-edge.repo > /dev/null <<'EOF'
[microsoft-edge]
name=Microsoft Edge
baseurl=https://packages.microsoft.com/yumrepos/edge
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# Microsoft prod repo
sudo tee /etc/yum.repos.d/microsoft-prod.repo > /dev/null <<EOF
[packages-microsoft-com-prod]
name=Microsoft Production
baseurl=https://packages.microsoft.com/fedora/${FEDORA_VERSION}/prod/
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# VS Code repo
sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

sudo dnf makecache

# ── Himmelblau stable repo ──────────────────────────────────────────────────

echo "  Installing Himmelblau signing key and repo…"
sudo dnf upgrade -y
sudo rpm --import https://packages.himmelblau-idm.org/himmelblau.asc
sudo tee /etc/yum.repos.d/himmelblau.repo > /dev/null <<EOF
[himmelblau]
name=Himmelblau
baseurl=https://packages.himmelblau-idm.org/stable/latest/rpm/${HIMMELBLAU_REPO_DISTRO}/
enabled=1
gpgcheck=1
gpgkey=https://packages.himmelblau-idm.org/himmelblau.asc
EOF

sudo dnf makecache

# ── Microsoft Edge ──────────────────────────────────────────────────────────

echo "  Installing Microsoft Edge…"
sudo dnf install -y microsoft-edge-stable

# ── Visual Studio Code ─────────────────────────────────────────────────────

echo "  Installing Visual Studio Code…"
sudo dnf install -y code

# ── Microsoft Identity Broker ───────────────────────────────────────────────

echo "  Installing Microsoft Identity Broker…"
install_if_available microsoft-identity-broker

# ── Intune Company Portal ───────────────────────────────────────────────────

echo "  Installing Intune Company Portal…"
install_if_available intune-portal

# ── linux-entra-sso native connector ────────────────────────────────────────

echo "  Installing linux-entra-sso native connector, if available…"
install_if_available linux-entra-sso

# ── Himmelblau ──────────────────────────────────────────────────────────────

configure_himmelblau

echo "  Installing Himmelblau without broker…"
sudo dnf install -y himmelblau pam-himmelblau nss-himmelblau

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files >/dev/null 2>&1; then
  sudo systemctl enable --now himmelblaud himmelblaud-tasks
else
  echo "  systemd is not available; start himmelblaud and himmelblaud-tasks manually after install."
fi

# ── YubiKey / Smart Card ────────────────────────────────────────────────────

echo "  Setting up YubiKey smart card support…"
sudo dnf install -y pcsc-lite pcsc-lite-ccid yubikey-manager opensc nss-tools openssl

mkdir -p "$HOME/.pki/nssdb"
chmod 700 "$HOME/.pki"
chmod 700 "$HOME/.pki/nssdb"
modutil -force -create -dbdir "sql:$HOME/.pki/nssdb"
OPENSC_PKCS11_MODULE="/usr/lib64/pkcs11/opensc-pkcs11.so"
if [ ! -f "$OPENSC_PKCS11_MODULE" ]; then
  echo "  OpenSC PKCS#11 module not found at $OPENSC_PKCS11_MODULE; install opensc and retry."
  exit 1
fi
modutil -force -dbdir "sql:$HOME/.pki/nssdb" -add 'SC Module' -libfile "$OPENSC_PKCS11_MODULE"

# ── Password policy (pam_pwquality) ─────────────────────────────────────────

sudo dnf install -y libpwquality
sudo install -d -m 755 /etc/security/pwquality.conf.d
sudo tee /etc/security/pwquality.conf.d/99-dotfiles.conf > /dev/null <<'EOF'
minlen = 12
dcredit = -1
ocredit = -1
ucredit = -1
lcredit = -1
retry = 3
EOF

# ── Microsoft Azure VPN client ──────────────────────────────────────────────

echo "  Installing Microsoft Azure VPN client…"
install_if_available microsoft-azurevpnclient

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
echo "    6. Review authselect/PAM before enabling any interactive Entra login flow."
echo "    7. Run: aad-tool auth-test --name ${HIMMELBLAU_LOCAL_USER}"
echo "       Use the same PIN/password as your local user so TPM unlock can happen on login."
echo "    8. Once Himmelblau compliance is confirmed, install himmelblau-broker manually to switch away from intune/identity-broker."
echo ""
