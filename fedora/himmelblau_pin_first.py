#!/usr/bin/env python3
"""Patch a NEW copied authselect profile, never the active/generated PAM stack."""

import sys
from pathlib import Path


PIN_RULE = "auth sufficient pam_himmelblau.so ignore_unknown_user set_authtok"
UNSEAL_RULE = "auth optional pam_himmelblau.so try_unseal"


def fields(line):
    return " ".join(line.split())


def patch_profile(profile, vendor):
    """Validate every input before writing; preserve all unrelated lines verbatim."""
    pending = {}
    for name in ("system-auth", "password-auth", "postlogin"):
        path = profile / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Refusing missing/symlinked template: {path}")
        lines = path.read_text().splitlines(keepends=True)
        kept = []
        for line in lines:
            words = line.split()
            if words and words[0] == "auth" and "pam_himmelblau.so" in words:
                allowed = (UNSEAL_RULE,) if name == "postlogin" else (PIN_RULE, UNSEAL_RULE)
                if fields(line) not in allowed:
                    raise ValueError(f"Unrecognized Himmelblau auth rule in {path}; review manually")
                continue
            kept.append(line)
        if name != "postlogin":
            # Use the installed vendor rule, but reject changed semantics/options.
            rules = [line for line in (vendor / name).read_text().splitlines()
                     if fields(line) == PIN_RULE]
            if len(rules) != 1:
                raise ValueError(f"Expected exactly one verified vendor PIN rule in {vendor / name}")
            if not any(line.split()[:3] == ["auth", "sufficient", "pam_unix.so"]
                       for line in kept):
                raise ValueError(f"No sufficient local pam_unix fallback in {path}; review manually")
            kept.insert(0, rules[0] + "\n")
        pending[path] = "".join(kept)

    for path, content in pending.items():
        # These are fresh, inactive copies; leave permissions/ownership intact.
        path.write_text(content)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: himmelblau_pin_first.py NEW_COPIED_PROFILE INSTALLED_VENDOR_PROFILE")
    try:
        patch_profile(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError) as exc:
        sys.exit(str(exc))
