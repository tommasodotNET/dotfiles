# Azure VPN on Fedora

## Preferred: native NetworkManager + Himmelblau

Use the real **GNOME Settings → Network → VPN** switch, with Entra authentication
through the existing Himmelblau broker and sso-mib. The Fedora 44 implementation
was validated and the owner confirmed the work application works.

- [Native setup, use, limitations and rollback](native/README.md)
- [Pinned package sources and authenticated local-build prerequisites](native/BUILD.md)

This is an **opt-in manual integration**, not part of recursive dotfiles setup.
It requires reviewed patched OpenVPN/NetworkManager packages; ordinary Fedora
packages do not provide this Entra flow. Private upstream patches are not
redistributed. The documented fixed-network startup/roaming limitations apply.
No automatic package swap, authentication, connection or boot-time VPN activation.

## Retained fallback: OpenP2S

[The existing pinned OpenP2S setup and launcher](OPENP2S.md) remain available and
unchanged. `bash ~/.dotfiles/azure-vpn/setup.sh --profile /private/path/profile.xml`
continues to mean **OpenP2S setup**, not native integration. Keep it as fallback;
**never run both clients simultaneously**. Disconnect and verify complete route /
DNS cleanup before switching.

Both paths need organisational approval and a separately supplied private Azure
XML. Never commit XML, generated profiles/dispatcher configuration, corporate
routes/DNS/endpoints, credentials, tokens, logs or binaries. Tests use synthetic
data only. Read the selected runbook before executing any setup command.
