# Himmelblau PIN-first login on Fedora

`setup_himmelblau.sh` provisions **new setups**, not an enrolled-machine repair.
It creates `custom/dotfiles-himmelblau-pin-first` as a copy of the selected
authselect profile. Starting from Fedora's working `local` profile gives local
account/password/session rules and local NSS with just this new first auth rule
in `system-auth` and `password-auth`, read from the installed vendor templates:

```text
auth sufficient pam_himmelblau.so ignore_unknown_user set_authtok
```

This tries the enrolled Himmelblau PIN before existing local authentication.
The local password remains the fallback; it need not equal the PIN. This also
affects SSH/sudo callers of these shared PAM stacks, not only graphical login.
An unavailable daemon can cause a timeout before local fallback succeeds.
Browser SSO, device compliance and keyring unlock are separate acceptance gates.

The helper removes only recognized old optional `try_unseal` auth hooks from
the copied templates (including `postlogin`) and deduplicates the PIN rule.
It requires a sufficient `pam_unix` fallback, rejects unknown Himmelblau auth
rules or symlinked templates, and validates all three files before writing.
It does not add vendor account/password/session rules, replace NSS, or change
the existing feature list. If the source already has other integrations, they
remain inherited; inspect them rather than assuming any custom source is local.
Fingerprint choice and hardware-specific TPM changes from another machine are
not propagated. The existing company-authorized OS-report override is retained.

## Safe creation and reruns

- Keep a working local administrator password and a privileged recovery session
  open before provisioning. Review the selected profile/features first.
- The script **refuses an existing destination**, even an incomplete profile or
  dangling symlink, before package/config changes. It never deletes the selected
  profile, its source, or an older `dotfiles-himmelblau-unseal` rollback profile.
- It backs up `/etc/authselect`, `/etc/pam.d`, `/etc/nsswitch.conf` and the original
  raw profile/features under the printed root-only
  `/var/backups/dotfiles-himmelblau/pam.*` directory before the general update and
  Himmelblau install. It first ensures authselect and its setup dependencies are
  installed; the backup is of authentication configuration, not enrollment state.
- Creation uses copied templates, not PAM symlinks. `authselect test` previews
  the new profile with the **original features** before selection.
- On a refusal or failure, inspect the existing destination and backup. Do not
  delete it just to rerun this whole setup, especially on an enrolled machine.
  A partial profile remains for inspection; review an explicit repair/migration
  instead. This is fail-closed handling, not a claim of full provisioning
  idempotence or automatic rollback of package/configuration changes.
- To roll back a selected profile through the retained privileged session, use
  `sudo authselect select ORIGINAL_PROFILE ORIGINAL_FEATURES --force` with the
  exact values from `authselect-current.txt`, then `sudo authselect check`.
  If the original source is damaged, inspect/restore the saved source first;
  do not force a selection against a missing profile.

## Acceptance on the newly provisioned machine

1. Complete private enrollment with `aad-tool auth-test --name LOCAL_USER` and
   keep credentials/PIN out of logs. Check `aad-tool status` and
   `sudo authselect check`.
2. Retain the privileged recovery session. Verify a **new** local-password login
   and password-based sudo, then independent key-only SSH where configured.
3. In an authorized recovery-test window, stop both `himmelblaud` and
   `himmelblaud-tasks`; repeat new local-password login and sudo with a timeout
   allowance. Restore both services on every exit path and verify their final
   state. Do not run a daemon-down test without recovery access.
4. For sudo proof use an explicit marker such as
   `sudo sh -c 'test "$(id -u)" = 0 && printf "RECOVERY_UID_ZERO_VERIFIED\n"'`
   after `sudo -k`. Require successful exit and the marker, not stdout exactly
   equal to `0`: PAM can emit diagnostics before a successful fallback.
5. Save work and test graphical logout/login with the private PIN. Only the
   actual user test establishes graphical PIN acceptance; PAM syntax and local
   fallback do not. Then follow [browser SSO setup](himmelblau-sso.md).

Source-only validation (no provisioning/PAM/service changes):

```sh
bash -n fedora/setup_himmelblau.sh
python3 -B -m unittest discover -s fedora/tests -v
```
