"""Offline tests: fixtures only, no sudo, authselect selection or system writes."""

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "pin_first", Path(__file__).resolve().parents[1] / "himmelblau_pin_first.py")
pin_first = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pin_first)


class PinFirstTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.profile = self.root / "copy"
        self.vendor = self.root / "vendor"
        self.profile.mkdir()
        self.vendor.mkdir()
        self.baseline = (
            "# copied local profile\n"
            "auth sufficient pam_fprintd.so {include if \"with-fingerprint\"}\n"
            "auth sufficient pam_unix.so {if not \"without-nullok\":nullok}\n"
            "account required pam_unix.so\n"
            "password sufficient pam_unix.so yescrypt use_authtok\n"
            "session required pam_unix.so\n")
        for name in ("system-auth", "password-auth"):
            (self.profile / name).write_text(self.baseline)
            (self.vendor / name).write_text(pin_first.PIN_RULE + "\n")
        (self.profile / "postlogin").write_text("session optional pam_lastlog.so\n")
        (self.profile / "nsswitch.conf").write_text("passwd: files systemd\n")

    def contents(self):
        return {p.name: p.read_text() for p in self.profile.iterdir()}

    def patch(self):
        pin_first.patch_profile(self.profile, self.vendor)

    def test_local_rules_features_nss_preserved_and_idempotent(self):
        before = self.contents()
        self.patch()
        for name in ("system-auth", "password-auth"):
            self.assertEqual((self.profile / name).read_text(),
                             pin_first.PIN_RULE + "\n" + before[name])
        for name in ("postlogin", "nsswitch.conf"):
            self.assertEqual((self.profile / name).read_text(), before[name])
        after = self.contents()
        self.patch()
        self.assertEqual(self.contents(), after)

    def test_legacy_unseal_removed_and_pin_deduplicated(self):
        for name in ("system-auth", "password-auth", "postlogin"):
            with (self.profile / name).open("a") as target:
                target.write(pin_first.UNSEAL_RULE + "\n")
                if name != "postlogin":
                    target.write(pin_first.PIN_RULE + "\n")
        self.patch()
        for name, content in self.contents().items():
            self.assertNotIn("try_unseal", content)
            if name in ("system-auth", "password-auth"):
                self.assertEqual(content, pin_first.PIN_RULE + "\n" + self.baseline)

    def assert_refused_without_writes(self):
        before = self.contents()
        with self.assertRaises(ValueError):
            self.patch()
        self.assertEqual(self.contents(), before)

    def test_unknown_hook_refused_before_any_write(self):
        with (self.profile / "postlogin").open("a") as target:
            target.write("auth required pam_himmelblau.so unknown_option\n")
        self.assert_refused_without_writes()

    def test_missing_local_fallback_refused(self):
        (self.profile / "password-auth").write_text("auth required pam_deny.so\n")
        self.assert_refused_without_writes()

    def test_changed_vendor_rule_refused(self):
        (self.vendor / "password-auth").write_text("auth required pam_himmelblau.so\n")
        self.assert_refused_without_writes()

    def test_symlink_refused_without_touching_source(self):
        source = self.root / "source-postlogin"
        (self.profile / "postlogin").rename(source)
        (self.profile / "postlogin").symlink_to(source)
        self.assert_refused_without_writes()


class RerunGuardTests(unittest.TestCase):
    def test_destination_guard_only_in_temporary_directories(self):
        script = (Path(__file__).resolve().parents[1] / "setup_himmelblau.sh").read_text()
        # Execute ONLY the early test/exit guard, never the provisioning script.
        start = script.index('if sudo test -e "$authselect_profile_dir"')
        guard = script[start:script.index("\nfi", start) + 3]
        self.assertLess(start, script.index("sudo dnf"))
        self.assertNotIn("sudo rm", script)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "existing").mkdir()
            (root / "existing" / "keep").write_text("preserved")
            (root / "dangling").symlink_to(root / "missing-source")
            (root / "file").write_text("preserved")
            for name, code in (("absent", 0), ("existing", 1), ("dangling", 1), ("file", 1)):
                with self.subTest(name=name):
                    result = subprocess.run(
                        ["bash", "-c", 'sudo() { "$@"; }; authselect_profile_dir="$1";\n' + guard,
                         "test-guard", str(root / name)], capture_output=True, text=True)
                    self.assertEqual(result.returncode, code, result.stderr)
            self.assertEqual((root / "existing" / "keep").read_text(), "preserved")
            self.assertTrue((root / "dangling").is_symlink())
            self.assertEqual((root / "file").read_text(), "preserved")


if __name__ == "__main__":
    unittest.main()
