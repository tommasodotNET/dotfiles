#!/usr/bin/env bash

set -euo pipefail

HIMMELBLAU_DOMAIN="${DOTFILES_HIMMELBLAU_DOMAIN:-microsoft.com}"
HIMMELBLAU_LOCAL_USER="${DOTFILES_HIMMELBLAU_LOCAL_USER:-tommasostocchi}"
HIMMELBLAU_UPN="${DOTFILES_HIMMELBLAU_UPN:-tstocchi@microsoft.com}"
AUTHSELECT_PROFILE_NAME="dotfiles-himmelblau-unseal"
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

echo "Updating Fedora..."
sudo dnf update -y

sudo dnf install -y authselect dnf-plugins-core

if ! authselect check >/dev/null 2>&1; then
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

echo "Adding the signed Himmelblau Community Nightly repository..."
sudo rpm --import "$HIMMELBLAU_KEY_URL"
sudo dnf config-manager --add-repo="$HIMMELBLAU_REPO_URL"
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
sudo chmod 600 /etc/himmelblau/user-map

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

echo "Configuring PAM for local authentication and TPM secret unlock only..."
sudo authselect select "$original_authselect_profile" \
	"${original_authselect_features[@]}" --force
sudo authselect apply-changes

sudo rm -rf "/etc/authselect/custom/${AUTHSELECT_PROFILE_NAME}"
sudo authselect create-profile "$AUTHSELECT_PROFILE_NAME" -b "$original_authselect_profile"
authselect_profile_dir="/etc/authselect/custom/${AUTHSELECT_PROFILE_NAME}"

for pam_file in system-auth password-auth; do
	sudo aad-tool configure-pam \
		--auth-file="${authselect_profile_dir}/${pam_file}" \
		--account-file="${authselect_profile_dir}/${pam_file}" \
		--session-file="${authselect_profile_dir}/${pam_file}" \
		--password-file="${authselect_profile_dir}/${pam_file}" \
		--try-unseal \
		--really
done

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
echo "  3. Install and test linux-entra-sso in Chrome or Firefox with the current Intune stack:"
echo "     https://github.com/siemens/linux-entra-sso"
echo ""
echo "Enroll this mapped user with:"
echo "  aad-tool auth-test --name ${HIMMELBLAU_LOCAL_USER}"
echo "Use the local user's password as the Himmelblau PIN so PAM can unlock it at login."
echo "Monitor enrollment with: journalctl -fu himmelblaud -u himmelblaud-tasks"
echo "Confirm compliance at: https://portal.manage-beta.microsoft.com/devices"
echo ""
echo "Only after compliance and browser SSO work, install himmelblau-broker manually."
