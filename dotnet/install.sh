#!/usr/bin/env bash
set -euo pipefail

echo "Installing .NET SDK 10.0.401"
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$installer"
bash "$installer" --version 10.0.401 --install-dir "$HOME/dotnet" --no-path

export DOTNET_ROOT="$HOME/dotnet"
export PATH="$DOTNET_ROOT:$PATH"
export SSL_CERT_DIR="$HOME/.aspnet/dev-certs/trust:/etc/pki/tls/certs${SSL_CERT_DIR:+:$SSL_CERT_DIR}"

echo "Trusting dotnet dev certs"
dotnet dev-certs https --trust
dotnet --version
