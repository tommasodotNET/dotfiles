# Native package provenance and local-source build gate

This public topic contains **no private upstream patch code**. `prepare.py` and
`dispatcher.py` adapt the independently authored integration from the validated
trial, not the private PR route helper. The dispatcher retains the tested
canonical-host/conflict/ownership fixes. The existing public OpenP2S fallback and
its GPL notice are unchanged. Repository MIT terms cover the authored integration;
private source rights do not change merely because it builds alongside GPL code.

## Required authenticated inputs (not downloadable anonymously from here)

Obtain authorised access to private `mcaps-microsoft/microsoft-loves-linux` PR #9,
head **`b1b92deed35055adfeb60ef72125436006392892`**, base
`ccd619d2404910267e343899ac60f7f479fed694`, first commit
`a8ef8da8ec44e3006f6bf7d68af69e9e54d328cf`. Use your approved authenticated
workflow; browser access does not imply GitHub CLI access. Do not export cookies,
put credentials in commands, publish patches or assume redistribution permission.
A 404/access failure is a source prerequisite blocker, not permission to reconstruct
private code from descriptions.

The reviewed build needs:

- Fedora signed SRPM `NetworkManager-openvpn-1.12.5-4.fc44.src.rpm`, including
  upstream 1.12.5 tarball and Fedora sysusers MR 104 patch. Tarball SHA-256
  `ce32e38b0500eddf2fc8072ca17679817fc2d35eb91f6ff7b9904209c14b5afd`.
- PR plugin patch **1** (management v6 long passwords) and **3** (Entra via
  sso-mib), applied in sequence. **Omit patch 2 entirely**: inline `ta-content`
  is unnecessary and has unsafe runtime key handling. Use the ordinary protected
  `ta` file. Patch 1 + 3 build independently. Preserve Fedora patch 104.
- Signed Fedora `openvpn-2.7.7-1.fc44.src.rpm`, its upstream archive and detached
  signature/signing key, crypto-policy patch and tmpfiles-permissions patch.
  Upstream v2.7.7 commit `85f07f7b784009adf90129b3854c5b742ca3cef9` already includes
  long-password management support; do **not** double-apply that PR patch.
- The reviewed local rebase of the PR TLS-record-buffer change for OpenVPN 2.7.7,
  SHA-256 `50895ec318b6f5001140f415a52177721a42264b303f3621e0f0193f55758188`.
  The original private patch has two rejected hunks on 2.7.7. The local rebase
  preserves the newer `to_link` lifetime check/function signature. **That exact
  reviewed local input is a separate prerequisite**; it is not distributed here.
  If unavailable, a newly reviewed port and fresh tests are required, not a forced
  patch application or removal of lifetime checks.
- Fedora sso-mib-devel/libs **0.8.0**, not an arbitrary latest version. Public
  [Siemens sso-mib](https://github.com/siemens/sso-mib) v0.8.0 source reference
  `5c7759fbe2649522575bb1d0224a6224e7ca217e`. This is a C library, not Rust.

Start with the Fedora SRPM specs; retain their patches, dependencies, license files,
source GPG verification and tests. Reviewed changes only: OpenVPN release
`1%{?dist}.nmtrial1`, added TLS-buffer Patch100; NM release
`4%{?dist}.nmtrial1`, Patch101/103, `BuildRequires: sso-mib-devel = 0.8.0`,
GTK3/GTK4 and sso-mib enabled. Exact already-reviewed SPECS/SOURCES can be reused
**locally** from the private trial tree; this recipe does not vendor those specs
or imply they can be published. Inspect all source/script execution before building.

## Isolated build, never host install

Use a new owner-only directory outside *any* Git repository, containing only
`SPECS/openvpn.spec`, `SPECS/NetworkManager-openvpn.spec`, required `SOURCES/`, and
`INPUT-SHA256SUMS` covering every spec/source. Verify signed Fedora inputs and
upstream source signatures **before** generating that reviewed manifest. A checksum
created from an untrusted file is not provenance. Do not include XML, cert/key,
profile, token caches or logs from authentication in the build mount.

```sh
bash ~/.dotfiles/azure-vpn/native/build-local.sh --help
# Explicit opt-in; downloads build dependencies only inside rootless Podman:
bash ~/.dotfiles/azure-vpn/native/build-local.sh "$HOME/private/nm-vpn-build"
```

Based on the tested rootless Fedora 44 build pinned to image
`registry.fedoraproject.org/fedora@sha256:cd3513b19e87220eb6fba1aeb041cf88f9c00c3b1de213c36db7532c383f4a1c`.
Only the private build directory is mounted; no host transaction, devices, HOME or
session bus. The image is pinned, but dependency repositories evolve: the package
manifest records resolved versions; **bit-for-bit reproducibility is not claimed**.
Version guards refuse a different spec release or sso-mib API baseline. Never
run this script as root or broaden mounts to overcome an access failure.

The original build passed OpenVPN crypto selftests/20 drivers, a TLS loopback test,
and NM import/export tests; extracted binaries linked correctly against host
libraries. Re-run those tests, inspect dependency/ABI compatibility and exact RPM
contents on a new build; the wrapper alone does not prove corporate auth or a
future fresh install. Resulting private local RPMs are unsigned. No RPM binaries,
SRPMs, patch bodies, source archive or build logs belong in this public repository.

## Review/install gate (manual, not scripted)

Acquire matching **signed** Fedora binary rollback RPMs for openvpn and both NM
plugin packages before replacement; verify Fedora signatures and hashes. Keep
all six candidate/rollback paths explicit. Inspect pending offline updates (DNF
can invalidate them), active OpenVPN units, and current package baseline. Stop if
the baseline has moved or package replacement would interrupt another VPN.
Use DNF `--assumeno install` with the **three exact local candidate paths** first;
review the transaction, then deliberately perform the approved local package
installation. Do not wildcard-install build output, turn off global signature
verification, or bypass queued updates with raw rpm. A normal unsigned local
build is not a signed Fedora update: verify trusted local-build provenance first.

Continue with [private profile preparation](README.md). No package installation,
new build, authentication or live connection was performed when adding this topic.
