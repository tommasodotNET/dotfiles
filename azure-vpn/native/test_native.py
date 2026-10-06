#!/usr/bin/env python3
"""Synthetic, rootless, offline regression tests; no VPN or host networking."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import uuid

HERE = Path(__file__).resolve().parent

def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

p = load('prepare')
d = load('dispatcher')


def xml():
    return f'''<AzVpnProfile><clientauth><type>aad</type><aad>
<tenant>https://login.microsoftonline.com/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee</tenant>
<audience>11111111-2222-3333-4444-555555555555</audience></aad></clientauth>
<protocolconfig><sslprotocolConfig><transportprotocol>tcp</transportprotocol></sslprotocolConfig></protocolconfig>
<serverlist><ServerEntry><fqdn>vpn.example.invalid</fqdn></ServerEntry></serverlist>
<servervalidation><Cert><hash>{'0' * 40}</hash></Cert><serversecret>{'0123456789abcdef' * 32}</serversecret></servervalidation>
<clientconfig><includeroutes><route><destination>10.0.0.0</destination><mask>8</mask></route></includeroutes>
<excluderoutes><route><destination>10.2.0.0</destination><mask>16</mask></route>
<route><destination>203.0.113.8</destination><mask>32</mask></route></excluderoutes>
<dnsservers><dnsserver>10.0.0.53</dnsserver></dnsservers><dnssuffixes><dnssuffix>.example.invalid</dnssuffix></dnssuffixes>
</clientconfig></AzVpnProfile>'''.encode()


class ProfileTests(unittest.TestCase):
    def test_valid_profile_and_exact_name(self):
        result = p.parse(xml())
        self.assertEqual(result['cn'], 'vpn.example.invalid')
        self.assertIn('203.0.113.8/32', result['exclusions'])
        explicit = xml().replace(b'</fqdn>', b'</fqdn><serverCN>exact.example.invalid</serverCN>')
        self.assertEqual(p.parse(explicit)['cn'], 'exact.example.invalid')

    def test_refusals_do_not_echo_private_input(self):
        cases = [b'<!DOCTYPE secret>' + xml(), b'<!ENTITY x "value">' + xml(), b'<PRIVATE>',
                 xml().replace(b'>tcp<', b'>udp<'), xml().replace(b'>aad<', b'>cert<'),
                 xml().replace(b'203.0.113.8', b'2001:db8::1'),
                 xml().replace(b'<mask>32</mask>', b'<mask>0</mask>'),
                 xml().replace(b'10.2.0.0', b'10.0.0.0').replace(b'<mask>16', b'<mask>8'),
                 xml().replace(b'</fqdn>', b'</fqdn><serverCN>*.example.invalid</serverCN>'),
                 xml().replace(b'<servervalidation>', b'<servervalidation><usepinnedroot>true</usepinnedroot>'),
                 xml().replace(b'</ServerEntry>', b'<fqdn>other.example.invalid</fqdn></ServerEntry>'),
                 xml().replace(b'<clientconfig>', b'<clientconfig><ipv6routes/>')]
        for case in cases:
            with self.subTest(case=cases.index(case)), self.assertRaises(ValueError) as caught:
                p.parse(case)
            self.assertNotIn('example.invalid', str(caught.exception))
            self.assertNotIn('PRIVATE', str(caught.exception))

    def test_libnm_keyfile_flags(self):
        result = p.connection(p.parse(xml()), Path('/home/example/.cert/test'), str(uuid.uuid4()))
        for expected in ('autoconnect=false', 'never-default=true', 'permissions=user:',
                         'password-flags=3', 'verify-x509-name=name:vpn.example.invalid', 'method=disabled'):
            self.assertIn(expected, result)
        self.assertNotIn('ta-content', result)
        self.assertNotIn('0123456789abcdef' * 32, result)

    def test_private_input_and_exclusive_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'private'
            p.write(f, 'test')
            self.assertEqual(f.stat().st_mode & 0o777, 0o600)
            self.assertEqual(p.private_read(f), b'test')
            with self.assertRaises(FileExistsError): p.write(f, 'overwrite')
            f.chmod(0o644)
            with self.assertRaises(ValueError): p.private_read(f)
            link = Path(tmp) / 'link'; link.symlink_to(f)
            with self.assertRaises(OSError): p.private_read(link)

    def test_guard_rejects_future_os(self):
        with patch.object(Path, 'read_text', return_value='ID=fedora\nVERSION_ID=45\n'):
            with self.assertRaises(ValueError): p.guard_versions()

    def test_help_is_inert(self):
        result = subprocess.run(['python3', '-B', str(HERE / 'prepare.py'), '--help'], capture_output=True)
        self.assertEqual(result.returncode, 0)
        result = subprocess.run(['bash', str(HERE / 'build-local.sh'), '--help'], capture_output=True)
        self.assertEqual(result.returncode, 0)


class DispatcherTests(unittest.TestCase):
    def test_host_canonicalization_and_foreign_preservation(self):
        row = dict(dst='203.0.113.8/32', gateway='192.0.2.1', dev='uplink0', protocol=197, metric=0)
        actual = dict(row, dst='203.0.113.8'); del actual['metric']
        self.assertTrue(d.exact(actual, row))
        for field, value in [('protocol', 198), ('gateway', '192.0.2.2'), ('dev', 'other'), ('metric', 4)]:
            self.assertFalse(d.exact(dict(actual, **{field: value}), row))
        self.assertFalse(d.exact(dict(actual, dst='bad'), row))

    def test_scoped_conflict_failed_add_and_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            c = Path(tmp) / 'config'; state = Path(tmp) / 'state'
            c.write_text(json.dumps({'uuid': 'test', 'exclusions': ['203.0.113.8/32']}))
            baseline = [dict(dst='default', gateway='192.0.2.1', dev='uplink0')]
            current = list(baseline)
            calls = []
            def run(a, check=True):
                calls.append(a)
                return subprocess.CompletedProcess(a, 0, '', '')
            with patch.object(d, 'C', c), patch.object(d, 'S', state), patch.object(d.os, 'geteuid', return_value=0), \
                 patch.dict(os.environ, {'CONNECTION_UUID': 'other', 'DEVICE_IP_IFACE': 'uplink0'}), \
                 patch.object(d.sys, 'argv', ['helper', 'uplink0', 'vpn-up']), \
                 patch.object(d, 'routes', side_effect=lambda: current), patch.object(d, 'run', side_effect=run):
                self.assertEqual(d.main(), 0); self.assertEqual(calls, [])
                os.environ['CONNECTION_UUID'] = 'test'
                current.append(dict(dst='203.0.113.8', metric=0, protocol=197))
                with self.assertRaises(ValueError): d.main()
                self.assertEqual(calls, [])
                current[:] = baseline
                with patch.object(d, 'run', return_value=subprocess.CompletedProcess([], 2, '', 'exists')):
                    with self.assertRaises(ValueError): d.main()
                self.assertFalse((state / 'journal.json').exists())
                self.assertEqual(d.main(), 0)
                owned = json.loads((state / 'journal.json').read_text())
                self.assertEqual(len(owned), 1)
                current.append(dict(owned[0], dst='203.0.113.8'))
                d.sys.argv[2] = 'vpn-down'
                self.assertEqual(d.main(), False)
                self.assertEqual(json.loads((state / 'journal.json').read_text()), [])
                self.assertEqual(calls[-1][3], 'del')


if __name__ == '__main__':
    unittest.main()
