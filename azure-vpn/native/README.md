# Native GNOME / NetworkManager Azure VPN (preferred)

Manual Fedora 44 integration using **NetworkManager + Himmelblau**, not a desktop
launcher pretending to be a VPN. GNOME Settings → Network → VPN owns the switch;
the normal desktop secret agent obtains Entra authentication through sso-mib and
the existing Himmelblau broker. This is a community/private-patch integration,
not a Microsoft-supported Linux client. Obtain organisational approval first.

[Azure VPN topic](../README.md) · [OpenP2S fallback](../OPENP2S.md) ·
[Package build/provenance gate](BUILD.md)

## Status and limits

Validated 2026-10-06: Fedora 44 x86-64, NetworkManager 1.56.1, patched
NetworkManager-openvpn 1.12.5 and OpenVPN 2.7.7, Himmelblau 4.0.0,
sso-mib-libs 0.8.0. Native authentication, corporate split DNS, bidirectional
traffic, public HTTPS and complete route/DNS restoration passed. Fresh privileged
inspection confirmed an empty ownership journal and matching installed helper /
config. The owner subsequently confirmed the work application works.
This records the existing installation, **not proof of a fresh install** of this
generalised recipe. Long sessions, renewal, suspend/resume and roaming remain
untested. Guards deliberately stop on different package versions, not silently
assume later Fedora releases work.

The small dispatcher is the tested fixed-uplink approach, **not a kill switch**:

- Exclusions are added at `vpn-up`, so there is a startup routing gap. Dispatcher
  failure requests disconnection but cannot veto NetworkManager activation.
- Parent interface comes from NetworkManager's `DEVICE_IP_IFACE`; the lowest
  metric IPv4 default on that physical interface supplies the gateway. Main-table,
  single-uplink IPv4 only; no ECMP, policy-routing or roaming safety guarantee.
- Never-default is enabled; pushed routes remain enabled and ordinary longest
  prefix rules still apply. More-specific pushed routes can outrank exclusions.
  IPv6 profile policy is rejected; disabling profile IPv6 is not a fail-closed
  security boundary against unexpected server pushes or non-VPN IPv6 traffic.
- Disconnect before changing networks or suspending. Reconnect manually afterwards.
  A green switch is not a test of application connectivity.
- Route destinations are canonicalised (including bare-IP versus `/32`);
  same-prefix metric-zero conflicts are refused before adding routes. Only
  successful additions are journalled. Cleanup deletes only exact recorded
  destination/gateway/device/protocol/metric tuples, preserving foreign routes.
  Protocol 197 alone is **never ownership proof**. A crash between add and journal
  save needs explicit private-baseline recovery; no blanket flush/reconstruction.
  An externally replaced route with an identical tuple is indistinguishable;
  do not have another manager rewrite these owned routes concurrently.

## 1. Deliberate prerequisites — no bootstrap integration

Read [BUILD.md](BUILD.md) first. Native Entra support is **not in the ordinary
Fedora plugin**. Authenticated access to pinned private source and a reviewed local
TLS-buffer rebase are required. No private patch body, source archive, RPM, profile
or account data is distributed here. Do not copy any into this public repository.

Before replacing packages: preserve signed matching Fedora rollback RPMs, reconcile
pending offline updates, inspect the exact DNF transaction and inactive OpenVPN
units. The build recipe runs in a rootless container only; it does not install on
the host. Do not use raw rpm or disable signature checking globally to bypass DNF.
Existing Himmelblau 4 broker/SSO must already work for the desktop user. Generic
Microsoft setup may omit the broker; do not blindly rerun enrollment or change PAM.
Follow [Himmelblau SSO documentation](../../fedora/himmelblau-sso.md) separately.
The GTK auth dialog needs sso-mib-libs 0.8.0; no Rust toolchain is needed.

Preparation needs Python 3 with PyGObject/libnm introspection, openssl, rpm,
restorecon, and NetworkManager 1.56.1. systemd-resolved and SELinux must remain
active. Install any missing prerequisite separately using normal Fedora tooling.
Scripts here are intentionally **not named install.sh**: recursive dotfiles setup
must never swap VPN packages, install a dispatcher or activate a connection.

## 2. Prepare private files offline (no root, no connection)

Keep the original Azure XML outside Git, owner-only mode 0600. It contains the TLS
static key and corporate network policy. The parser supports one TCP/aad gateway,
Azure public authority, GUID audience, IPv4 includes/exclusions, and explicit split
DNS. Unsupported XML shapes, DTD/entities, IPv6/default policies, ambiguous equal
prefixes and pinned-root policy fail instead of being weakened.

```sh
python3 -B ~/.dotfiles/azure-vpn/native/prepare.py --help
python3 -B ~/.dotfiles/azure-vpn/native/prepare.py \
  --profile "$HOME/private/azurevpnconfig.xml"
```

The existing trusted-root extractor selects **only the root matching the XML
thumbprint** from Fedora's trust bundle, and verifies its validity/self-signature.
`--trust-bundle` is only for another already-trusted bundle, never downloaded trust.
The server name is the explicit `ServerEntry/serverCN` if supplied, otherwise the
single FQDN (the tested schema). It is used as **exact** `verify-x509-name=name:...`;
no wildcard, substring or disabled TLS verification. A different certificate naming
scheme requires profile review, not guessing a name from an unverified connection.

Output is exclusively `~/.cert/dotfiles-azure-vpn/` (new directory 0700, files
0600): CA, normal `ta.key`, a private XML copy, keyfile, dispatcher JSON and UUID.
Existing output is refused. On failure, inspect/move partial output privately
before retrying. Nothing is installed/reloaded/activated. `restorecon` applies the
standard certificate-home label and verifies `home_cert_t` on CA/key. Do not use
`ta-content`, a root-only unreadable user key, custom policy or permissive SELinux.
The keyfile is user-restricted, `autoconnect=no`, `never-default=yes`, IPv6 disabled,
and Azure password flags **3** (agent-owned + not-saved), with no persisted token.

## 3. Explicit deployment after private review

Do this only on a machine not already configured. Do **not** deploy a second copy
alongside an existing trial dispatcher/profile. Disconnect all VPNs/OpenP2S first;
review active connections/processes, the generated private files, existing target
paths, and save route/DNS baseline privately. Never print these files into CI/chat.
The following refuses existing destinations rather than overwriting configuration.
Run each step deliberately; none is called by preparation or generic bootstrap:

```sh
private="$HOME/.cert/dotfiles-azure-vpn"
# Inspect existing files first. If any exist, stop and review; do not overwrite.
sudo test ! -e /etc/NetworkManager/dispatcher.d/90-dotfiles-azure-vpn &&
sudo test ! -e /etc/NetworkManager/dotfiles-azure-vpn.json &&
sudo test ! -e /etc/NetworkManager/system-connections/dotfiles-azure-vpn.nmconnection &&
sudo install -o root -g root -m 0700 \
  "$HOME/.dotfiles/azure-vpn/native/dispatcher.py" \
  /etc/NetworkManager/dispatcher.d/90-dotfiles-azure-vpn &&
sudo install -o root -g root -m 0600 "$private/dispatcher.json" \
  /etc/NetworkManager/dotfiles-azure-vpn.json &&
sudo install -o root -g root -m 0600 "$private/profile.nmconnection" \
  /etc/NetworkManager/system-connections/dotfiles-azure-vpn.nmconnection &&
sudo restorecon /etc/NetworkManager/dispatcher.d/90-dotfiles-azure-vpn \
  /etc/NetworkManager/dotfiles-azure-vpn.json \
  /etc/NetworkManager/system-connections/dotfiles-azure-vpn.nmconnection &&
sudo nmcli connection load \
  /etc/NetworkManager/system-connections/dotfiles-azure-vpn.nmconnection
```

Do not restart NetworkManager. Verify profile flags and permissions locally.
The root-only runtime journal is `/run/dotfiles-azure-vpn/journal.json`.
A partial deployment must be inspected before retrying; do not remove a live
helper/config or overwrite somebody else's files. Installation is not connection.

## 4. Connect and verify manually

Keep a local terminal/recovery path available for the first connection, and arrange
a bounded local disconnect before remote testing. There is **no permanent timer**
or automatic reconnect controller in this topic. GNOME Settings → Network → VPN →
**Azure VPN (NetworkManager)**, or (as the desktop user):

```sh
uuid=$(cat "$HOME/.cert/dotfiles-azure-vpn/uuid")
nmcli connection up uuid "$uuid"
# After use, or immediately if routing/public access fails:
nmcli --wait 15 connection down uuid "$uuid"
```

Allow normal broker/MFA prompts. Never paste tokens or use `G_MESSAGES_DEBUG=ssomib`
(it can expose D-Bus values). Check while **still activated**: corporate split DNS
on the tunnel, actual work application, RX/TX counters, public HTTPS, every expected
route, and the *current connected transport peer* on the physical interface. Do
not mistake teardown-time probes or an old DNS answer for active-tunnel proof.
After disconnect, verify the full saved all-table routes and resolved DNS baseline,
no remaining VPN/OpenVPN process, and an empty root-only ownership journal.

## Fallback and rollback

**Never run native VPN and OpenP2S simultaneously.** Turn native OFF, verify route /
DNS cleanup, then use the unchanged [OpenP2S fallback](../OPENP2S.md). Package
rollback is not required merely to use that fallback's separate bundled OpenVPN.
If cleanup fails, stop: preserve journal and private baseline; do not delete routes
by protocol, flush tables, remove the journal, or start another client over it.

For package rollback, first disconnect and prove cleanup. Keep copies of profile,
helper/config and private evidence. Verify signatures with `rpmkeys --checksig`
and recorded SHA-256 hashes on the **three exact signed Fedora originals**:
OpenVPN `2.7.7-1.fc44`, NetworkManager-openvpn and -gnome `1:1.12.5-4.fc44`.
Check pending offline updates and active OpenVPN units again; preview an explicit
`sudo dnf --assumeno downgrade /absolute/path/to/each/of/the/three.rpm` transaction,
then repeat with the three actual paths only after approval/review. No wildcard,
unsigned rollback, removal of Himmelblau/sso-mib or broad network restart.
On future package versions obtain matching signed originals and re-review this
pinned recipe rather than silently downgrading a newer security baseline.

To retire native integration, after cleanup back up/delete only its UUID via
`nmcli connection delete uuid "$uuid"`, then move its dedicated helper, JSON and
certificate directory to a private backup. Preserve the original XML, OpenP2S,
all unrelated VPNs and broker state. Never remove a dispatcher while it still owns
routes. Rollback commands are a manual runbook, not executed/tested by this update.

## Offline regression checks

```sh
python3 -B ~/.dotfiles/azure-vpn/native/test_native.py
python3 -B ~/.dotfiles/azure-vpn/test_setup.py
bash -n ~/.dotfiles/azure-vpn/native/build-local.sh
# Optional: actual kernel routes, isolated rootless namespace ONLY (never sudo):
unshare --user --map-root-user --net \
  python3 -B ~/.dotfiles/azure-vpn/native/test_netns.py
```

Synthetic data only. No installer, packages, private source, authentication, live
VPN or host networking is needed for these checks.
