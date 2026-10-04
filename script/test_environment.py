from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
GENERATOR = Path(
    "/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator"
)


class EnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles environment ")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.root = self.home / ".dotfiles"
        for source in [
            ROOT / "script/link-environment",
            ROOT / "system/environment.zsh",
            *ROOT.glob("*/environment.conf"),
        ]:
            target = self.root / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        self.env = {
            "HOME": str(self.home),
            "PATH": "/usr/bin:/bin",
            "XDG_CONFIG_HOME": str(self.home / "custom-config"),
            "LC_ALL": "C",
        }
        self.destination = self.home / "custom-config/environment.d"

    def link(self, check=True):
        return subprocess.run(
            ["bash", str(self.root / "script/link-environment")],
            env=self.env, text=True, capture_output=True, check=check,
        )

    def desktop_environment(self):
        if not GENERATOR.exists():
            self.skipTest("systemd environment.d generator is required")
        result = subprocess.run(
            [str(GENERATOR)], env=self.env, text=True,
            capture_output=True, check=True,
        )
        return dict(shlex.split(line)[0].split("=", 1) for line in result.stdout.splitlines())

    def shell_environment(self):
        result = subprocess.run(
            [
                "zsh", "-f", "-c",
                'source "$HOME/.dotfiles/system/environment.zsh" && '
                'source "$HOME/.dotfiles/system/environment.zsh" && /usr/bin/env',
            ],
            env=self.env, text=True, capture_output=True, check=True,
        )
        return dict(line.split("=", 1) for line in result.stdout.splitlines())

    def test_fresh_setup_and_rerun(self):
        self.link()
        links = sorted(self.destination.iterdir())
        self.assertEqual(len(links), len(list(self.root.glob("*/environment.conf"))))
        for link in links:
            topic = link.name.removeprefix("60-dotfiles-").removesuffix(".conf")
            self.assertTrue(link.is_symlink())
            self.assertEqual(link.resolve(), self.root / topic / "environment.conf")
        self.assertEqual(self.link().stdout, "")

    def test_default_config_directory(self):
        self.env.pop("XDG_CONFIG_HOME")
        self.link()
        self.assertTrue(
            (self.home / ".config/environment.d/60-dotfiles-go.conf").is_symlink()
        )

    def test_migrate_only_managed_legacy_link(self):
        self.destination.mkdir(parents=True)
        legacy = self.destination / "60-fnm.conf"
        legacy.symlink_to(self.root / "system/60-fnm.conf")
        self.link()
        self.assertFalse(legacy.is_symlink())
        legacy.write_text("EXISTING=value\n")
        self.link()
        self.assertEqual(legacy.read_text(), "EXISTING=value\n")

    def test_conflict_does_not_overwrite_or_partially_link(self):
        self.destination.mkdir(parents=True)
        conflict = self.destination / "60-dotfiles-go.conf"
        conflict.write_text("EXISTING=value\n")
        result = self.link(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to replace unmanaged", result.stderr)
        self.assertEqual(list(self.destination.iterdir()), [conflict])
        self.assertEqual(conflict.read_text(), "EXISTING=value\n")

    def test_shell_and_desktop_share_paths_and_exported_variables(self):
        self.link()
        desktop = self.desktop_environment()
        shell = self.shell_environment()
        for name in [
            "PATH", "DOTNET_ROOT", "GOPATH", "FNM_PATH", "PNPM_HOME",
            "JAVA_HOME", "ANDROID_HOME", "ANDROID_SDK_ROOT",
        ]:
            self.assertEqual(shell[name], desktop[name], name)
        paths = shell["PATH"].split(":")
        self.assertEqual(len(paths), len(set(paths)))
        for directory in [
            "/usr/local/go/bin", str(self.home / "go/bin"),
            str(self.home / ".dotnet/tools"), str(self.home / ".local/bin"),
            str(self.home / ".local/share/fnm/aliases/default/bin"),
        ]:
            self.assertIn(directory, paths)

    def test_new_topic_and_edits_are_automatically_discovered(self):
        self.link()
        topic = self.root / "example"
        topic.mkdir()
        config = topic / "environment.conf"
        config.write_text("EXAMPLE_HOME=${HOME}/example\nPATH=${EXAMPLE_HOME}/bin:${PATH}\n")
        self.link()
        for environment in [self.desktop_environment(), self.shell_environment()]:
            self.assertEqual(environment["EXAMPLE_HOME"], str(self.home / "example"))
            self.assertIn(str(self.home / "example/bin"), environment["PATH"].split(":"))
        config.write_text("EXAMPLE_HOME=${HOME}/updated\nPATH=${EXAMPLE_HOME}/bin:${PATH}\n")
        for environment in [self.desktop_environment(), self.shell_environment()]:
            self.assertEqual(environment["EXAMPLE_HOME"], str(self.home / "updated"))

    def test_invalid_shell_declaration_reports_failure(self):
        (self.root / "go/environment.conf").write_text("this-command-does-not-exist\n")
        with self.assertRaises(subprocess.CalledProcessError):
            self.shell_environment()


if __name__ == "__main__":
    unittest.main()
