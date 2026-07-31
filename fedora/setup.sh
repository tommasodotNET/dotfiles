#!/usr/bin/env bash

set -euo pipefail

if [[ ! -r /etc/os-release ]]; then
    echo "Unable to identify this operating system." >&2
    exit 1
fi

source /etc/os-release
if [[ "${ID:-}" != "fedora" ]]; then
    echo "This setup script only supports Fedora." >&2
    exit 1
fi

configure_dnf() {
    local config_file=/etc/dnf/dnf.conf
    local temporary_file

    temporary_file=$(mktemp)
    trap 'rm -f "$temporary_file"' RETURN

    sudo awk '
        BEGIN {
            settings["max_parallel_downloads"] = "10"
            settings["defaultyes"] = "True"
            settings["keepcache"] = "True"
        }
        /^\[main\][[:space:]]*$/ {
            in_main = 1
            found_main = 1
            print
            next
        }
        /^\[/ {
            if (in_main) {
                for (key in settings) {
                    if (!seen[key]) print key "=" settings[key]
                }
            }
            in_main = 0
        }
        in_main && /^[[:space:]]*(max_parallel_downloads|defaultyes|keepcache)[[:space:]]*=/ {
            key = $0
            sub(/^[[:space:]]*/, "", key)
            sub(/[[:space:]]*=.*/, "", key)
            print key "=" settings[key]
            seen[key] = 1
            next
        }
        { print }
        END {
            if (in_main) {
                for (key in settings) {
                    if (!seen[key]) print key "=" settings[key]
                }
            } else if (!found_main) {
                print "[main]"
                for (key in settings) print key "=" settings[key]
            }
        }
    ' "$config_file" > "$temporary_file"

    sudo install -m 644 "$temporary_file" "$config_file"
}

echo "Configuring DNF..."
configure_dnf

echo "Updating Fedora..."
sudo dnf -y update

echo "Enabling RPM Fusion free and nonfree repositories..."
sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

echo "Ensuring the Fedora RPM Fusion repositories are enabled..."
sudo dnf config-manager setopt rpmfusion-free.enabled=1
sudo dnf config-manager setopt rpmfusion-free-updates.enabled=1
sudo dnf config-manager setopt rpmfusion-free-rawhide.enabled=0

echo "Installing multimedia codecs..."
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf group upgrade -y multimedia
sudo dnf group upgrade -y core

echo "Fedora setup complete. Reboot to finish applying system and codec updates."