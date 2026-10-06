#!/usr/bin/env python3
"""Offline native profile preparation; never installs, connects or authenticates."""
import argparse
import getpass
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET

TOPIC = Path(__file__).resolve().parent
CLIENT = 'c632b3df-fb67-4d84-bdcf-b95ad541b5c8'  # public Azure VPN application


def require(ok, message):
    if not ok:
        raise ValueError(message)


def private_read(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        st = os.fstat(fd)
        require(stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid() and not st.st_mode & 0o077,
                'Private input must be an owner-only regular file')
        require(st.st_size <= 4 * 1024 * 1024, 'Input too large')
        return os.read(fd, 4 * 1024 * 1024 + 1)
    finally:
        os.close(fd)


def hostname(value):
    require(len(value) <= 253 and '.' in value and all(re.fullmatch(
        r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', x) for x in value.split('.')),
        'Invalid DNS name')
    return value


def parse(raw):
    require(len(raw) <= 4 * 1024 * 1024 and b'<!DOCTYPE' not in raw.upper()
            and b'<!ENTITY' not in raw.upper(), 'Unsupported XML declarations or size')
    try:
        root = ET.fromstring(raw)
        for e in root.iter():
            e.tag = e.tag.rsplit('}', 1)[-1]
        require(root.tag == 'AzVpnProfile', 'Unsupported profile root')

        def text(path):
            items = root.findall(path)
            require(len(items) == 1 and items[0].text is not None, 'Missing or duplicate XML field')
            return items[0].text.strip()

        require(text('clientauth/type') == 'aad', 'Only aad authentication supported')
        require(text('protocolconfig/sslprotocolConfig/transportprotocol').lower() == 'tcp', 'Only TCP supported')
        tenant = text('clientauth/aad/tenant').rstrip('/')
        require(re.fullmatch(r'https://login\.microsoftonline\.com/[0-9a-fA-F-]{36}', tenant), 'Unsupported authority')
        uuid.UUID(tenant.rsplit('/', 1)[1])
        audience = str(uuid.UUID(text('clientauth/aad/audience')))
        for e in root.findall('.//clientid'):
            require(not e.text or e.text.strip() == CLIENT, 'Client ID requires review')
        host = hostname(text('serverlist/ServerEntry/fqdn'))
        # Tested profile uses its gateway FQDN as exact certificate CN.
        # Honor an explicit serverCN when supplied; never use a wildcard/substr match.
        names = root.findall('serverlist/ServerEntry/serverCN')
        require(len(names) <= 1, 'Duplicate serverCN')
        cn = text('serverlist/ServerEntry/serverCN') if names else host
        require(re.fullmatch(r'[A-Za-z0-9._-]{1,253}', cn), 'Exact serverCN required; no wildcard')
        require(root.findtext('servervalidation/type', 'cert').strip().lower() == 'cert', 'Unsupported server validation')
        secret = text('servervalidation/serversecret')
        require(re.fullmatch(r'[a-fA-F0-9]{512}', secret), 'Invalid static key')
        require(root.findtext('servervalidation/usepinnedroot', 'false').strip().lower() in ('false', '0'),
                'Unsupported pinned-root policy')
        fingerprint = text('servervalidation/Cert/hash').replace(':', '').lower()
        require(re.fullmatch('[0-9a-f]{40}', fingerprint), 'Invalid CA fingerprint')

        def routes(group):
            result = set()
            for e in root.findall('clientconfig/' + group + '/route'):
                require(len(e) == 2 and {x.tag for x in e} == {'destination', 'mask'}, 'Unsupported route field')
                n = ipaddress.ip_network(e.findtext('destination').strip() + '/' + e.findtext('mask').strip(), strict=False)
                require(n.version == 4 and n.prefixlen != 0, 'IPv6/default policy requires review')
                result.add(str(n))
            return sorted(result)

        inc, exc = routes('includeroutes'), routes('excluderoutes')
        require(not set(inc) & set(exc), 'Ambiguous equal include/exclude prefix')
        dns = [str(ipaddress.IPv4Address(e.text.strip())) for e in root.findall('clientconfig/dnsservers/dnsserver')]
        suffix = [hostname(e.text.strip().lstrip('.')) for e in root.findall('clientconfig/dnssuffixes/dnssuffix')]
        require(dns and suffix, 'Explicit split DNS servers and suffixes required')
        # Do not silently accept separately named IPv6 policy fields.
        require(not any('ipv6' in e.tag.lower() for e in root.iter()), 'IPv6 policy requires review')
        return dict(host=host, cn=cn, secret=secret, fingerprint=fingerprint, tenant=tenant,
                    audience=audience, includes=inc, exclusions=exc, dns=dns, suffix=suffix)
    except (ET.ParseError, AttributeError, TypeError, ValueError):
        raise ValueError('Unsupported or malformed Azure XML; review locally without logging secrets') from None


def guard_versions():
    release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
    require(release.get('ID', '').strip('"') == 'fedora' and release.get('VERSION_ID', '').strip('"') == '44',
            'Only Fedora 44 was validated; review before porting')
    pins = {'NetworkManager': '1.56.1', 'NetworkManager-openvpn': '1.12.5',
            'NetworkManager-openvpn-gnome': '1.12.5', 'openvpn': '2.7.7', 'sso-mib-libs': '0.8.0'}
    for package, version in pins.items():
        actual = subprocess.check_output(['rpm', '-q', '--qf', '%{VERSION}', package], text=True)
        require(actual == version, 'Package version differs from validated baseline: ' + package)
    for package in ('NetworkManager-openvpn', 'NetworkManager-openvpn-gnome', 'openvpn'):
        release = subprocess.check_output(['rpm', '-q', '--qf', '%{RELEASE}', package], text=True)
        expected = '4.fc44.nmtrial1' if package.startswith('NetworkManager') else '1.fc44.nmtrial1'
        require(release == expected, 'Reviewed patched RPM required: ' + package)
    require(subprocess.check_output(['rpm', '-q', '--qf', '%{VERSION}', 'himmelblau'], text=True).startswith('4.'),
            'Himmelblau 4 required')


def write(path, content):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), 'w') as stream:
        stream.write(content)


def connection(p, destination, identity):
    import gi
    gi.require_version('NM', '1.0')
    from gi.repository import NM
    c = NM.SimpleConnection.new()
    s = NM.SettingConnection.new()
    s.props.id = 'Azure VPN (NetworkManager)'
    s.props.uuid = identity
    s.props.type = 'vpn'
    s.props.autoconnect = False
    s.add_permission('user', getpass.getuser(), None)
    c.add_setting(s)
    vpn = NM.SettingVpn.new()
    vpn.props.service_type = 'org.freedesktop.NetworkManager.openvpn'
    data = {'username': 'AzureAD', 'connection-type': 'entra', 'remote': p['host'], 'port': '443',
            'proto-tcp': 'yes', 'dev-type': 'tun', 'ca': str(destination / 'ca.pem'),
            'ta': str(destination / 'ta.key'), 'ta-dir': '1', 'verify-x509-name': 'name:' + p['cn'],
            'remote-cert-tls': 'server', 'tls-version-min': '1.2', 'cipher': 'AES-256-GCM',
            'data-ciphers': 'AES-256-GCM', 'data-ciphers-fallback': 'AES-256-GCM', 'auth': 'SHA256',
            'reneg-seconds': '0', 'entra-client-id': CLIENT, 'entra-authority': p['tenant'],
            'entra-scope': p['audience'] + '/.default', 'entra-redirect-uri': 'http://localhost:2023',
            'password-flags': '3'}
    for k, v in data.items():
        vpn.add_data_item(k, v)
    vpn.set_secret_flags('password', NM.SettingSecretFlags.AGENT_OWNED | NM.SettingSecretFlags.NOT_SAVED)
    c.add_setting(vpn)
    v4 = NM.SettingIP4Config.new()
    v4.props.method = 'auto'
    v4.props.route_table = 254
    v4.props.ignore_auto_routes = False
    v4.props.ignore_auto_dns = False
    v4.props.never_default = True
    v4.props.auto_route_ext_gw = 1
    v4.props.routed_dns = 0
    for value in p['includes']:
        n = ipaddress.IPv4Network(value)
        v4.add_route(NM.IPRoute.new(socket.AF_INET, str(n.network_address), n.prefixlen, None, 0))
    for d in p['dns']:
        v4.add_dns(d)
    for d in p['suffix']:
        v4.add_dns_search('~' + d)
    c.add_setting(v4)
    v6 = NM.SettingIP6Config.new()
    v6.props.method = 'disabled'
    c.add_setting(v6)
    require(c.verify(), 'libnm validation failed')
    return NM.keyfile_write(c, NM.KeyfileHandlerFlags.NONE, None, None).to_data()[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--trust-bundle', type=Path, default=Path('/etc/pki/tls/certs/ca-bundle.crt'))
    args = parser.parse_args()
    require(os.geteuid() != 0, 'Run as the desktop user, never root')
    require(not args.profile.resolve().is_relative_to(TOPIC.parents[1]), 'Keep private XML outside dotfiles')
    guard_versions()
    raw = private_read(args.profile)
    p = parse(raw)
    os.umask(0o077)
    dest = Path.home() / '.cert/dotfiles-azure-vpn'
    require(dest.parent.resolve() == dest.parent.absolute(), 'Certificate parent must not use symlinks')
    require(not dest.exists() and not dest.is_symlink(), 'Destination exists; refuse overwrite')
    dest.parent.mkdir(mode=0o700, exist_ok=True)
    # Reuse the existing trusted-root extraction/validity checks, not private PR code.
    spec = importlib.util.spec_from_file_location('vpn_profile', TOPIC.parent / 'profile.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    require(module.prepare(args.profile, args.trust_bundle, dest) == p['host'], 'Gateway changed')
    require((dest / 'profile.xml').read_bytes() == raw, 'Profile changed during preparation')
    key = '-----BEGIN OpenVPN Static key V1-----\n' + '\n'.join(p['secret'][i:i+32].lower() for i in range(0, 512, 32)) + '\n-----END OpenVPN Static key V1-----\n'
    write(dest / 'ta.key', key)
    identity = str(uuid.uuid4())
    content = connection(p, dest, identity)
    require('ta-content' not in content and p['secret'] not in content, 'Inline secret refused')
    write(dest / 'profile.nmconnection', content)
    write(dest / 'dispatcher.json', json.dumps({'uuid': identity, 'exclusions': p['exclusions']}) + '\n')
    write(dest / 'uuid', identity + '\n')
    subprocess.run(['restorecon', '-R', str(dest)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for name in ('ca.pem', 'ta.key'):
        require(b':home_cert_t:' in os.getxattr(dest / name, 'security.selinux'), 'Expected home_cert_t certificate label')
    print('Prepared owner-only files under ~/.cert/dotfiles-azure-vpn; nothing installed or activated.')
    print('Review native/README.md for explicit deployment and rollback. Never publish generated files.')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Native VPN preparation refused. Check prerequisites/profile locally; partial private output may remain. No live changes.', file=sys.stderr)
        sys.exit(1)
