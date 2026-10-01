# Azure VPN on Fedora — reproducible community-client trial

Optional Linux x86-64 setup for an organisation-approved Azure Point-to-Site
profile using Microsoft Entra ID authentication. **Not supported by Microsoft.**
The official Azure VPN Client for Linux retired on 2026-08-31. Ordinary
NetworkManager/OpenVPN does not implement this sign-in and compatibility flow.

This topic preserves the working Corellia trial, not a claim that every Azure
VPN profile or company policy is supported. Obtain approval to use a community
client. Never change tenant permissions, Conditional Access, MFA, or gateway
policy just to make this installer succeed.

## What is pinned

- [OpenP2S 0.2.1](https://github.com/wyruweso/openp2s/tree/v0.2.1), source commit
  `b6dc0216242d2adea643847ddd266e1bbc6730df`.
- Release archive `openp2s-0.2.1-linux-amd64.tar.gz`, SHA-256
  `3877a670221906810bb13dcd7e714c9dda7cd9820e70c4240fc7d88ada0be676`.
- Bundled OpenVPN **2.7.6**, SHA-256
  `8c00591c80bcc3498107a92784fcc07323b016e7b4b64ce651f615366d27ec7a`.
- Portable CLI SHA-256
  `b2514247df882cd3e9bf12c869f9d8725580d701ac69744c01d317c24f97960c`.
  Both binaries must also pass `gh attestation verify --repo wyruweso/openp2s`
  against the public signed release bundles retained in `attestations/`, enforcing
  the source commit above. These are signed upstream metadata, not local reports
  or credentials. GitHub CLI independently verifies their signature/trust chain.
- `openp2s-routes.patch` is the complete local source delta, **including new
  regression tests**. It preserves included/excluded IPv4 routes with explicit
  gateways/netmasks, rejects unsupported IPv6 policy, and protects the outer
  VPN endpoint with `route remote_host 255.255.255.255 net_gateway`.
  Gateway-pushed routes remain enabled; normal longest-prefix precedence applies.
- The runtime CLI is the **patched TypeScript source**, not the unpatched
  portable CLI. `npm ci --ignore-scripts` uses the upstream lockfile; the complete
  format/lint/type/test suite must pass before anything is installed.
- The manual launcher explicitly enables `--experimental-azure-compat`, required
  by the tested gateway. This changes Azure-style advertised client information,
  not the cipher implementation; TLS validation, AES-256-GCM, and Entra controls
  remain enabled. It uses the public Microsoft Azure VPN client application ID
  `c632b3df-fb67-4d84-bdcf-b95ad541b5c8`. Your tenant must already allow it for your
  profile's audience; this installer never grants consent or changes the audience.

The patch derives from OpenP2S and remains under **GPL-2.0-only**; its upstream
license is preserved in `OPENP2S-LICENSE`. Binary distribution notices and
corresponding-source links remain in the downloaded bundle.

## Prerequisites (deliberate, separate steps)

Tested platform: Fedora 44 Workstation x86-64 with systemd-resolved already active,
a graphical desktop/browser, `/dev/net/tun`, and normal interactive sudo rights.
No sudoers changes or passwordless sudo are needed. Never run setup as root.

Install missing prerequisites using Fedora's normal package manager if needed:

```sh
sudo dnf install git curl gh python3 openssl ca-certificates iproute sudo
# Node setup is an existing dotfiles topic, not automatically run by VPN setup:
bash ~/.dotfiles/node/install.sh
node --version
systemctl is-active systemd-resolved
```

Use **Node 24.13.0 or later in the 24.x series**, with npm beside its executable.
The selected absolute Node path/version is saved; update it only by a reviewed
rebuild, not by silently replacing its runtime. `--node /absolute/path/to/node`
selects another Node 24 installation. Python 3.12+ is required for safe archive
extraction (Fedora 44 supplies a newer version). GitHub CLI must support
`gh attestation verify`; release downloads, npm registry access, and Sigstore/GitHub
trust metadata retrieval must work. Stored signed bundles permit verification
without signing into a GitHub account. Setup fails if attestations cannot be
verified; there is no bypass switch and no token belongs in dotfiles.

Obtain the **original private Azure XML** from your organisation. Store it
outside the repository, preferably in an owner-only directory with mode 0600.
It contains a shared TLS secret and internal network configuration, even before
sign-in. Do not paste it into an issue, copy it here, or commit generated output.
The topic's `.gitignore` is defence in depth, not permission to keep secrets here.

Supported installer subset: `AzVpnProfile`, `aad`, one gateway FQDN, TCP,
IPv4 route policy, and a root SHA-1 thumbprint that matches a valid self-signed CA
already present in Fedora's trusted certificate bundle. Missing/unsupported
policy fails closed. Profiles setting `usepinnedroot=true` are refused because
this upstream release rejects that policy, even with an explicit CA; no weakening
override is added. Other profile shapes require review rather than conversion.

The installer extracts **only the matching root** from the existing system trust
bundle; it does not trust a certificate supplied by the XML and does not modify
system trust. `--trust-bundle` may select another **already trusted** local bundle;
never use an unverified downloaded CA to get past a failure. The launcher requires
an **exact server certificate CN equal to the single profile FQDN**, as verified
in the original trial. A different naming convention requires separate review:
do not remove `--verify-name`. Live chain/name validation happens on connection;
setup does not perform a handshake or claim to verify a remote server offline.

## Install explicitly

```sh
bash ~/.dotfiles/azure-vpn/setup.sh --help
bash ~/.dotfiles/azure-vpn/setup.sh \
  --profile "$HOME/private/azurevpnconfig.xml"
```

The filename is an example, not a tracked fixture. Setup stages a fresh pinned
checkout, bundle, and dependencies in an isolated owner-only directory; verifies
checksums, attestations, provenance, patched-source tests and profile parsing;
then publishes these **new** paths (public build/verification output is retained
in an owner-only `verification.log` under the installation):

- `~/.local/share/dotfiles-azure-vpn/`: source, dependencies, verified bundle,
  private profile/CA, settings, integrity manifest, local copy of this README.
- `~/.local/bin/azure-vpn`: manual launcher.
- `~/.local/share/applications/azure-vpn.desktop`: **Azure VPN (OpenP2S trial)**.

All three destinations must be absent. Rerunning refuses instead of overwriting
or updating an existing installation. A late publication error can leave part of
these *new* paths; inspect and move them aside before retrying. Setup never
replaces `~/repos/openp2s`, `~/.config/openp2s`, the earlier `msft-azure-vpn`
launcher, or its desktop entry. On the already-configured Corellia there is no
need to install this second copy merely to record the recipe. Do not run both
launchers simultaneously; OpenP2S uses shared per-user session/cache locations.

No service, autostart entry, NetworkManager profile, system DNS file, sudo
policy, or GNOME setting is changed. This script is named **setup.sh**, not
install.sh, so recursive `script/install` does not run it.

## Use

```sh
~/.local/bin/azure-vpn doctor      # read-only local diagnostics; can show private metadata
~/.local/bin/azure-vpn login       # optional, explicit Microsoft browser sign-in
~/.local/bin/azure-vpn connect     # or open Azure VPN (OpenP2S trial) from Applications
~/.local/bin/azure-vpn status
~/.local/bin/azure-vpn disconnect
```

Enter your **local laptop password only at the sudo prompt**, then complete
Microsoft sign-in/MFA in the browser if requested. Cached sign-in is reused when
permitted. Keep the connection terminal open; **Ctrl+C** gracefully disconnects.
Do not run the whole launcher with sudo. Login without a connection is optional;
connect performs sign-in as needed. Routine commands produce no persistent log
file in this wrapper (terminal output can still contain private metadata).

There is **no native GNOME Settings → VPN switch**. OpenP2S 0.2.1 has no
NetworkManager integration; the desktop entry is a terminal-based manual launcher.
Do not fake a NetworkManager entry that reports success independently of the VPN.

## Verify after a deliberate connection

Before connecting, save local `ip -json route show table all` and `resolvectl status`
output **privately** outside Git. After connecting, verify:

1. Actual tunnel interface/address agree with status. Status may be stale after
   an unexpected reconnect; the kernel interface is the authoritative check.
2. The **actual connected TCP peer**, not a freshly resolved/possibly rotated
   gateway address, routes over the physical interface, not the tunnel.
3. Required included/excluded routes and per-link split DNS are installed.
4. An organisation-approved internal hostname resolves through the VPN and its
   intended application works. Check tunnel RX/TX and normal public HTTPS too.
5. Ctrl+C disconnects, removes the tunnel, and restores the baseline routes/DNS.

Original Corellia evidence (2026-10-01): **581 tests passed**, short live tunnel,
bidirectional traffic, corporate split DNS, full profile route installation,
public HTTPS and complete cleanup. That is historical evidence, **not proof of a
future installation**. Specific work applications, long sessions, token renewal,
sleep/wake and roaming remain to be tested. If reconnect breaks DNS/state,
disconnect/reconnect manually rather than trusting an old connected indicator.

## Secrets, updates, and rollback

OpenP2S stores MSAL tokens in `~/.local/state/openp2s/cache/`: owner-only but
**not encrypted/keyring-backed**. Protect the account and disk accordingly.
Runtime credential files are cleaned up on normal disconnect. Neither tokens nor
profile data belong in dotfiles, backups shared publicly, CI artifacts or logs.

Installed file hashes detect accidental changes, including source/dependency
bytes and the local profile/CA; they are not a defence against an attacker who
can modify the user account and the manifest. Do not edit the installed source,
run npm update, update the profile, or swap the bundle in place. A change to the
upstream commit, patch, binary, Node or profile requires reviewed verification and
a fresh installation. This intentionally pinned recipe does not silently track
latest releases; check security updates before reuse.

To retire/rebuild: disconnect first, verify routes/DNS cleanup, then move the
three generated paths above into a private backup directory (do not remove the
original private profile or unrelated client installations). For example, after
those checks, move each path manually and reinstall into the now-empty paths.
If revoking cached login, use the installed source CLI's `auth clear --help` and
select only the intended profile/client ID; the shared cache may be used by the
older trial. Do not print token files or blindly delete the whole cache.
No system-package downgrade, trust-store change or network-service restart is
needed to remove this user-level setup.

## Offline regression checks for this topic

```sh
bash -n ~/.dotfiles/azure-vpn/setup.sh
python3 -B ~/.dotfiles/azure-vpn/test_setup.py
```

Tests use synthetic profiles and temporary homes only: no corporate XML, token
cache, sudo, authentication, VPN connection or network configuration changes.
The installer additionally runs the actual patched upstream checks when invoked.

References: [OpenP2S](https://github.com/wyruweso/openp2s),
[Linux client retirement](https://learn.microsoft.com/en-us/azure/vpn-gateway/azure-vpn-client-linux-retirement),
[NetworkManager VPN architecture](https://networkmanager.dev/docs/vpn/).
