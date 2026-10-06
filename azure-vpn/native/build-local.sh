#!/usr/bin/env bash
# Explicit isolated build of already-reviewed private SPECS/SOURCES. Never install.
set -euo pipefail
if [[ $# == 1 && $1 == --help ]]; then
  echo 'Usage: build-local.sh /absolute/private/build-tree (see BUILD.md)'; exit 0
fi
[[ $# == 1 && $1 == /* && $EUID != 0 ]] || { echo 'Supply one private absolute build tree; never run as root.' >&2; exit 1; }
work=$(realpath -- "$1")
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
[[ $work != "$repo" && $work != "$repo/"* ]] || { echo 'Private build input must stay outside Git.' >&2; exit 1; }
[[ -d $work/SPECS && -d $work/SOURCES && ! -e $work/RPMS && ! -e $work/logs ]] || { echo 'Use a fresh private input tree; outputs exist or inputs missing.' >&2; exit 1; }
[[ $(stat -c %u "$work") == "$UID" && $(stat -c %a "$work") == 700 ]] || { echo 'Build tree must be owned by you, mode 0700.' >&2; exit 1; }
# This validates exact reviewed inputs, not provenance: obtain the manifest through
# the separately authenticated source/review workflow described in BUILD.md.
[[ -f $work/INPUT-SHA256SUMS ]] || { echo 'Missing reviewed input hash manifest.' >&2; exit 1; }
# Require an exact, regular-file-only manifest: no symlink escape or omitted inputs.
python3 - "$work" <<'VERIFY'
import hashlib, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
actual = set()
for directory in ('SPECS', 'SOURCES'):
    base = root / directory
    assert not base.is_symlink(), 'Symlink input directory refused'
    for p in base.rglob('*'):
        assert not p.is_symlink(), 'Symlink input refused'
        if p.is_file(): actual.add(str(p.relative_to(root)))
        else: assert p.is_dir(), 'Special input refused'
seen = set()
for line in (root / 'INPUT-SHA256SUMS').read_text().splitlines():
    m = re.fullmatch(r'([0-9a-f]{64})  ((?:SPECS|SOURCES)/[^\n]+)', line)
    assert m, 'Use sha256sum format and only SPECS/SOURCES inputs'
    digest, name = m.groups()
    assert '..' not in pathlib.PurePosixPath(name).parts and name in actual and name not in seen
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, 'Input hash mismatch'
    seen.add(name)
assert seen == actual, 'Manifest must cover every source/spec exactly'
VERIFY
image=registry.fedoraproject.org/fedora@sha256:cd3513b19e87220eb6fba1aeb041cf88f9c00c3b1de213c36db7532c383f4a1c
umask 077
mkdir "$work/logs"
# Only build data mounted, never HOME, broker sockets, devices or profile directories.
podman run --rm --security-opt=no-new-privileges -v "$work:/work:Z" "$image" /bin/bash -s <<'BUILD'
set -euo pipefail
exec > /work/logs/build.log 2>&1
source /etc/os-release
[[ $ID == fedora && $VERSION_ID == 44 ]]
dnf -y install rpm-build redhat-rpm-config dnf5-plugins gcc make patch diffutils findutils gnupg2
[[ $(rpmspec -q --srpm --qf '%{VERSION}-%{RELEASE}' /work/SPECS/openvpn.spec) == 2.7.7-1.fc44.nmtrial1 ]]
[[ $(rpmspec -q --srpm --qf '%{VERSION}-%{RELEASE}' /work/SPECS/NetworkManager-openvpn.spec) == 1.12.5-4.fc44.nmtrial1 ]]
! grep -qE '^Patch[^:]*:.*0002-Allow' /work/SPECS/NetworkManager-openvpn.spec
dnf -y builddep /work/SPECS/openvpn.spec /work/SPECS/NetworkManager-openvpn.spec
[[ $(rpm -q --qf '%{VERSION}' sso-mib-devel) == 0.8.0 ]]
rpm -qa | sort > /work/build-package-manifest.txt
rpmbuild --define '_topdir /work' --define '_smp_mflags -j6' -ba /work/SPECS/openvpn.spec
rpmbuild --define '_topdir /work' --define '_smp_mflags -j6' -ba /work/SPECS/NetworkManager-openvpn.spec
find /work/RPMS /work/SRPMS -name '*.rpm' -exec sha256sum {} + > /work/SHA256SUMS
BUILD
printf '%s\n' 'Isolated build complete. No host packages changed. Review private logs/tests/RPMs; do not publish.'
