#!/usr/bin/env bash

set -euo pipefail

HIMMELBLAU_DOMAIN="${DOTFILES_HIMMELBLAU_DOMAIN:-microsoft.com}"
HIMMELBLAU_LOCAL_USER="${DOTFILES_HIMMELBLAU_LOCAL_USER:-tommasostocchi}"
HIMMELBLAU_UPN="${DOTFILES_HIMMELBLAU_UPN:-tstocchi@microsoft.com}"
AUTHSELECT_PROFILE_NAME="dotfiles-himmelblau-pin-first"
authselect_profile_dir="/etc/authselect/custom/${AUTHSELECT_PROFILE_NAME}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HIMMELBLAU_KEY_URL="https://packages.himmelblau-idm.org/himmelblau.asc"

if [[ ! -r /etc/os-release ]]; then
	echo "Unable to identify this operating system." >&2
	exit 1
fi

source /etc/os-release
if [[ "${ID:-}" != "fedora" ]]; then
	echo "This setup script only supports Fedora." >&2
	exit 1
fi

if ! id "$HIMMELBLAU_LOCAL_USER" >/dev/null 2>&1; then
	echo "Local user '$HIMMELBLAU_LOCAL_USER' does not exist." >&2
	exit 1
fi

if [[ "$HIMMELBLAU_UPN" != *@* ]]; then
	echo "DOTFILES_HIMMELBLAU_UPN must be a full Entra ID user principal name." >&2
	exit 1
fi

FEDORA_TARGET="fedora${VERSION_ID}"
HIMMELBLAU_REPO_URL="https://packages.himmelblau-idm.org/nightly/latest/rpm/${FEDORA_TARGET}"

echo "Configuring Himmelblau for ${HIMMELBLAU_LOCAL_USER}:${HIMMELBLAU_UPN}..."
echo "Using Community Nightly packages for ${FEDORA_TARGET}."

# Fail closed on reruns, including partial runs. Never delete/recreate a profile
# that may be selected, a rollback option, or the source of this operation.
if sudo test -e "$authselect_profile_dir" || sudo test -L "$authselect_profile_dir"; then
	echo "Profile $authselect_profile_dir already exists; refusing to replace it." >&2
	echo "Review fedora/himmelblau-login.md before any rerun; no profile was deleted." >&2
	exit 1
fi

sudo dnf install -y authselect dnf-plugins-core python3

if ! sudo authselect check >/dev/null 2>&1; then
	echo "The existing authselect configuration is invalid; refusing to modify PAM." >&2
	exit 1
fi

read -r -a authselect_state <<< "$(authselect current --raw)"
if (( ${#authselect_state[@]} == 0 )); then
	echo "Unable to determine the current authselect profile." >&2
	exit 1
fi
original_authselect_profile="${authselect_state[0]}"
original_authselect_features=("${authselect_state[@]:1}")

# Save the working local recovery path before package/configuration changes.
sudo install -d -m 700 /var/backups/dotfiles-himmelblau
auth_backup_dir="$(sudo mktemp -d /var/backups/dotfiles-himmelblau/pam.XXXXXXXX)"
sudo cp -a /etc/authselect /etc/pam.d /etc/nsswitch.conf "$auth_backup_dir/"
printf '%s\n' "${authselect_state[*]}" | sudo tee "$auth_backup_dir/authselect-current.txt" >/dev/null
echo "Authentication backup: $auth_backup_dir (keep a privileged recovery session open)."

echo "Updating Fedora..."
sudo dnf update -y

echo "Adding the signed Himmelblau Community Nightly repository..."
sudo rpm --import "$HIMMELBLAU_KEY_URL"
sudo dnf config-manager addrepo --id=himmelblau-nightly \
	--set="name=Himmelblau Community Nightly" \
	--set="baseurl=$HIMMELBLAU_REPO_URL" \
	--set="enabled=1" --set="gpgcheck=1" \
	--set="gpgkey=$HIMMELBLAU_KEY_URL" --add-or-replace
sudo dnf makecache -y

echo "Writing Himmelblau mapped-user configuration..."
sudo install -d -m 755 /etc/himmelblau
sudo tee /etc/himmelblau/himmelblau.conf >/dev/null <<EOF
[global]
domain = ${HIMMELBLAU_DOMAIN}
enable_experimental_mfa = true
enable_experimental_passwordless_fido = true
apply_policy = true
enable_experimental_intune_custom_compliance = true
hsm_type = tpm
join_type = register
user_map_file = /etc/himmelblau/user-map
local_groups = users
home_attr = CN
home_alias = CN
use_etc_skel = true
EOF

printf '%s:%s\n' "$HIMMELBLAU_LOCAL_USER" "$HIMMELBLAU_UPN" \
	| sudo tee /etc/himmelblau/user-map >/dev/null
# This non-secret localname:UPN map must be readable by himmelblaud's DynamicUser.
# Keep ownership/writes restricted to root; unreadable maps silently lose local IDs.
sudo chown root:root /etc/himmelblau/user-map
sudo chmod 644 /etc/himmelblau/user-map

echo "Configuring the Fedora compliance compatibility override..."
sudo install -d -m 755 /etc/systemd/system/himmelblaud-tasks.service.d
sudo tee /etc/systemd/system/himmelblaud-tasks.service.d/override.conf >/dev/null <<'EOF'
[Service]
BindReadOnlyPaths=/var/lib/fake-os-release:/usr/lib/os-release
EOF

sudo tee /var/lib/fake-os-release >/dev/null <<'EOF'
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
sudo chmod 644 /var/lib/fake-os-release

echo "Installing Himmelblau without the broker package..."
sudo dnf install -y himmelblau pam-himmelblau nss-himmelblau

echo "Configuring Himmelblau PIN-first authentication with local password fallback..."
# Package hooks may have selected another profile. Restore the captured baseline
# before preparing the new copy, so a validation failure keeps that login path.
sudo authselect test "$original_authselect_profile" \
	"${original_authselect_features[@]}" >/dev/null
sudo authselect select "$original_authselect_profile" \
	"${original_authselect_features[@]}" --force
# A copied profile preserves the prior account/password/session/NSS rules and
# features. Do not select the full vendor profile or symlink its PAM templates.
# create-profile itself refuses an existing destination (including a race here).
sudo authselect create-profile "$AUTHSELECT_PROFILE_NAME" -b "$original_authselect_profile"
sudo python3 "$script_dir/himmelblau_pin_first.py" "$authselect_profile_dir" \
	/usr/share/authselect/vendor/himmelblau

# Preview/validate the complete profile and original feature set before selection.
sudo authselect test "custom/${AUTHSELECT_PROFILE_NAME}" \
	"${original_authselect_features[@]}" >/dev/null
sudo authselect select "custom/${AUTHSELECT_PROFILE_NAME}" \
	"${original_authselect_features[@]}" --force
sudo authselect apply-changes
sudo authselect check

sudo systemctl daemon-reload
sudo systemctl enable --now himmelblaud himmelblaud-tasks

echo ""
echo "Himmelblau base setup complete. The broker was not installed."
echo ""
echo "Before enrollment:"
echo "  1. Enroll your YubiKey as a passkey: https://mysignins.microsoft.com/security-info"
echo "  2. Verify FIDO2 access: https://aka.ms/fido2 and https://aka.ms/fido2optin"
echo ""
echo "Enroll this mapped user with:"
echo "  aad-tool auth-test --name ${HIMMELBLAU_LOCAL_USER}"
echo "Login now tries the enrolled Himmelblau PIN first, then local authentication."
echo "The PIN need not match the local password; retain the local password for recovery."
echo "Follow fedora/himmelblau-login.md for graphical and daemon-down recovery tests."
echo "Monitor enrollment with: journalctl -fu himmelblaud -u himmelblaud-tasks"
echo "Confirm compliance at: https://portal.manage-beta.microsoft.com/devices"
echo ""
echo "Optional browser SSO (after mapped-user enrollment):"
echo "  1. Follow fedora/himmelblau-sso.md to check for a conflicting Microsoft broker"
echo "     and install the himmelblau-broker version matching the installed Himmelblau."
echo "     Himmelblau 5.0.0 uses a static D-Bus-activated user service; do not enable it."
echo "  2. Install linux-entra-sso's native helper AND browser extension:"
echo "     https://github.com/siemens/linux-entra-sso"
echo "  3. Test helper account/cookie responses, then browser website SSO and compliance."
echo "Fresh installs need no cache clearing; see the guide only for stale mapped IDs."
