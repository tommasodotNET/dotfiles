#!/usr/bin/env python3
"""Offline/synthetic tests: no VPN, account authentication, sudo or route changes."""
import hashlib
import importlib.util
import os
from pathlib import Path
import runpy
import ssl
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

TOPIC = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('vpn_profile', TOPIC / 'profile.py')
profile_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile_module)


def synthetic_xml(fingerprint):
    # Documentation-only hostname and synthetic key; never a corporate profile.
    return f'''<AzVpnProfile><clientauth><type>aad</type><aad>
<tenant>https://login.microsoftonline.com/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee</tenant>
<audience>c632b3df-fb67-4d84-bdcf-b95ad541b5c8</audience>
</aad></clientauth><serverlist><ServerEntry><fqdn>vpn.example.invalid</fqdn></ServerEntry></serverlist>
<servervalidation><Cert><hash>{fingerprint}</hash></Cert>
<serversecret>{'0123456789abcdef' * 32}</serversecret></servervalidation></AzVpnProfile>'''


class ProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='azure-vpn-unit-')
        cls.base = Path(cls.temp.name)
        cls.ca = cls.base / 'ca.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-noenc', '-days', '1',
                        '-subj', '/CN=Dotfiles synthetic test root', '-addext', 'basicConstraints=critical,CA:TRUE',
                        '-keyout', str(cls.base / 'test.key'), '-out', str(cls.ca)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        cls.fingerprint = hashlib.sha1(ssl.PEM_cert_to_DER_cert(cls.ca.read_text())).hexdigest()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def check_profile(self, xml):
        with tempfile.TemporaryDirectory(dir=self.base) as temp:
            temp = Path(temp)
            source = temp / 'input.xml'
            source.write_text(xml)
            result = profile_module.prepare(source, self.ca, temp / 'private')
            self.assertEqual(result, 'vpn.example.invalid')
            self.assertEqual((temp / 'private/profile.xml').read_bytes(), source.read_bytes())
            self.assertEqual((temp / 'private/profile.xml').stat().st_mode & 0o777, 0o600)
            self.assertEqual((temp / 'private/ca.pem').stat().st_mode & 0o777, 0o600)
            self.assertEqual((temp / 'private').stat().st_mode & 0o777, 0o700)

    def test_matching_trusted_root_and_private_permissions(self):
        self.check_profile(synthetic_xml(self.fingerprint))

    def test_unknown_root_refused(self):
        with self.assertRaisesRegex(ValueError, 'root not uniquely found'):
            self.check_profile(synthetic_xml('0' * 40))

    def test_unsupported_pin_policy_refused(self):
        with self.assertRaisesRegex(ValueError, 'policy is unsupported'):
            self.check_profile(synthetic_xml(self.fingerprint).replace('<servervalidation>', '<servervalidation><usepinnedroot>true</usepinnedroot>'))

    def test_multiple_gateways_refused(self):
        with self.assertRaisesRegex(ValueError, 'Exactly one gateway'):
            self.check_profile(synthetic_xml(self.fingerprint).replace('</serverlist>', '<ServerEntry><fqdn>other.example.invalid</fqdn></ServerEntry></serverlist>'))

    def test_non_aad_refused(self):
        with self.assertRaisesRegex(ValueError, 'aad authentication'):
            self.check_profile(synthetic_xml(self.fingerprint).replace('<type>aad', '<type>cert'))

    def test_udp_refused(self):
        with self.assertRaisesRegex(ValueError, 'Only TCP'):
            self.check_profile(synthetic_xml(self.fingerprint).replace('</AzVpnProfile>', '<protocolconfig><sslprotocolConfig><transportprotocol>udp</transportprotocol></sslprotocolConfig></protocolconfig></AzVpnProfile>'))

    def test_doctype_refused(self):
        with self.assertRaisesRegex(ValueError, 'declarations'):
            self.check_profile('<!DOCTYPE secret>' + synthetic_xml(self.fingerprint))

    def test_malformed_xml_does_not_echo_input(self):
        with self.assertRaisesRegex(ValueError, '^Malformed XML profile$'):
            self.check_profile('<PRIVATE_BROKEN_INPUT>')


class SetupSafetyTests(unittest.TestCase):
    def invoke(self, home, *args):
        env = os.environ.copy()
        env['HOME'] = str(home)
        return subprocess.run([sys.executable, '-B', str(TOPIC / 'setup.py'), *args], env=env,
                              capture_output=True, text=True)

    def test_help_does_not_install(self):
        with tempfile.TemporaryDirectory() as home:
            result = self.invoke(home, '--help')
            self.assertEqual(result.returncode, 0)
            self.assertEqual(list(Path(home).iterdir()), [])

    def test_missing_profile_refused_before_writes(self):
        with tempfile.TemporaryDirectory() as home:
            result = self.invoke(home, '--profile', str(Path(home) / 'absent.xml'))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('regular, non-symlink profile', result.stderr)
            self.assertEqual(list(Path(home).iterdir()), [])

    def test_all_existing_destinations_refused_unchanged(self):
        for relative in ['.local/share/dotfiles-azure-vpn', '.local/bin/azure-vpn', '.local/share/applications/azure-vpn.desktop']:
            with self.subTest(path=relative), tempfile.TemporaryDirectory() as home:
                dest = Path(home) / relative
                dest.parent.mkdir(parents=True)
                dest.write_text('preserve existing data')
                result = self.invoke(home, '--profile', '/does/not/exist.xml')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Refusing to overwrite', result.stderr)
                self.assertEqual(dest.read_text(), 'preserve existing data')

    def test_dangling_destination_symlink_refused(self):
        with tempfile.TemporaryDirectory() as home:
            dest = Path(home) / '.local/bin/azure-vpn'
            dest.parent.mkdir(parents=True)
            dest.symlink_to(Path(home) / 'absent')
            result = self.invoke(home, '--profile', '/does/not/exist.xml')
            self.assertIn('Refusing to overwrite', result.stderr)
            self.assertTrue(dest.is_symlink())

    def test_launcher_missing_install_fails_before_subprocess(self):
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, {'HOME': home}), \
                patch.object(sys, 'argv', ['azure-vpn', 'connect']), \
                patch('subprocess.run') as run, patch('os.execv') as execute:
            with self.assertRaises(SystemExit) as error:
                runpy.run_path(str(TOPIC / 'launcher.py'), run_name='__main__')
            self.assertIn('refusing to run', str(error.exception))
            run.assert_not_called()
            execute.assert_not_called()

    def test_optional_not_auto_discovered(self):
        self.assertFalse((TOPIC / 'install.sh').exists())
        self.assertIn('python3', (TOPIC / 'setup.sh').read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
