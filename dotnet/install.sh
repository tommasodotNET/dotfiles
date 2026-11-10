#!/usr/bin/env bash
set -euo pipefail

# dotnetup itself is currently in public preview; "latest" selects a stable SDK.
dotnetup="$HOME/.dotnetup/dotnetup"
if [[ ! -x "$dotnetup" ]]; then
    echo "Installing dotnetup"
    installer=$(mktemp)
    trap 'rm -f "$installer"' EXIT
    curl -fsSL https://aka.ms/dotnetup/get-dotnetup.sh -o "$installer"
    bash "$installer" --install-dir "$HOME/.dotnetup"
fi

export DOTNET_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/dotnetup/dotnet"
export PATH="$HOME/.dotnetup:$DOTNET_ROOT:$PATH"
export SSL_CERT_DIR="$HOME/.aspnet/dev-certs/trust:/etc/pki/tls/certs${SSL_CERT_DIR:+:$SSL_CERT_DIR}"

# Keep environment wiring in environment.conf (shared by Zsh and desktop apps),
# rather than letting interactive init append another block to shell profiles.
echo "Installing the latest stable .NET SDK with dotnetup"
"$dotnetup" sdk install latest --install-path "$DOTNET_ROOT" --no-progress

echo "Trusting dotnet dev certs"
"$DOTNET_ROOT/dotnet" dev-certs https --trust
"$DOTNET_ROOT/dotnet" --version
