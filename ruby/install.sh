#!/usr/bin/env bash
set -euo pipefail
source /etc/os-release
case "$ID" in
  fedora) sudo dnf install -y ruby ruby-devel rubygems make gcc ;;
  ubuntu|debian) sudo apt install -y ruby ruby-dev rubygems make gcc ;;
  *) echo "Unsupported Ruby bootstrap OS: $ID" >&2; exit 1 ;;
esac
sudo gem install colorls --no-document
