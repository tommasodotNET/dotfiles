# Optional Himmelblau browser SSO

`setup_himmelblau.sh` installs the base stack, not the broker. Browser SSO is a
separate, ordered stage: `linux-entra-sso` needs a broker **before** SSO testing.
Do not wait for working browser SSO or compliance before installing that broker.

## Ordered setup

1. Complete mapped-user enrollment using the command printed by the setup script.
   `/etc/himmelblau/user-map` contains non-secret `localname:UPN` mappings and must
   be owned by `root:root`, mode `0644`: only root may write it, but Himmelblau 5's
   DynamicUser daemon must be able to read it. An unreadable map can be silently
   ignored, leaving cloud-derived IDs instead of the local user's UID/GID.
   Verify the mapped UPN resolves to the local user's numeric IDs before SSO:

   ```sh
   # Substitute the enrolled local user and UPN.
   id LOCAL_USER
   getent -s himmelblau passwd 'UPN'
   ```

2. Check for an existing Microsoft Identity Broker before installing
   `himmelblau-broker`. Do not run competing brokers side by side. If a Microsoft
   broker is installed or active, stop this stage and explicitly review migration
   of that stack first; do not automatically remove packages or use
   `--allowerasing` to resolve conflicts.

   Inspect the installed Himmelblau version and use the existing signed
   Himmelblau repository to install the **matching version/release** of
   `himmelblau-broker`. Review DNF's transaction before accepting; do not take an
   unrelated newer nightly broker or replace another broker implicitly.

   ```sh
   rpm -q himmelblau pam-himmelblau nss-himmelblau
   # Example only for an installed 5.0.0-1 stack; substitute the actual version.
   sudo dnf install himmelblau-broker-5.0.0-1
   rpm -q himmelblau himmelblau-broker
   ```

   On Himmelblau 5.0.0 the broker is a **static, D-Bus-activated user service**.
   Use the enrolled local user's graphical session/session bus for SSO, not a
   root session. Let the packaged D-Bus activation start it when requested;
   it does not need `systemctl enable` or `systemctl --user enable`.

3. Install both the [linux-entra-sso native helper and browser extension](https://github.com/siemens/linux-entra-sso)
   for Chrome or Firefox, following upstream instructions. Verify native
   messaging from that browser profile, then check helper responses in the
   enrolled user's session: `getAccounts` should find the enrolled account and
   `acquirePrtSsoCookie` should return a nonempty SSO cookie without an error.
   Do not print, save or share token/cookie contents; record only success/counts.

4. Test actual browser website SSO and tenant/device compliance separately.
   Successful helper → broker → daemon account/cookie responses do **not** prove
   either website access or compliance. Both still require acceptance testing.

## Repair only: an already-cached wrong mapped UID/GID

**Fresh installs need no cache clearing.** If an existing enrollment cached
cloud-derived IDs while the map was unreadable, correcting permissions alone
may leave stale identity data. Do not rerun the whole provisioning script as a
cache-repair procedure.

Before changing an enrolled installation, preserve a root-only backup of its
configuration/map and a consistent backup of its enrolled cache (use SQLite's
online backup facility for a live database, not a raw copy of an open database).
Keep a working local administrator/recovery session available. Verify the map's
contents, root ownership and `0644` permissions first. Then, on the affected host
only, restart the daemon to read the corrected map and use the documented
**default** cache refresh:

```sh
sudo systemctl restart himmelblaud
sudo aad-tool cache-clear
getent -s himmelblau passwd 'UPN'
```

The default `aad-tool cache-clear` marks cached identities stale; the explicit
Himmelblau NSS lookup refreshes the mapping. **Never use `--full` for this repair**:
retain enrollment, HSM keys and credentials; do not delete or edit the database.
Check that the refreshed UID/GID matches `id LOCAL_USER`, then retry the helper
checks and browser tests in order. If the mapping remains wrong, investigate
instead of escalating to a destructive reset.
