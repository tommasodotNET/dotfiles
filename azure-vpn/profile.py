"""Offline preparation of the supported Azure XML shape. Never prints profile data."""
import hashlib
import re
import ssl
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path


def prepare(profile: Path, bundle: Path, output: Path) -> str:
    raw = profile.read_bytes()
    if len(raw) > 4 * 1024 * 1024 or b'<!DOCTYPE' in raw.upper() or b'<!ENTITY' in raw.upper():
        raise ValueError('Unsupported XML size or declarations')
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        raise ValueError('Malformed XML profile') from None
    for element in root.iter():
        element.tag = element.tag.split('}')[-1]
    if root.tag != 'AzVpnProfile' or root.findtext('clientauth/type') != 'aad':
        raise ValueError('Only AzVpnProfile with aad authentication is supported')
    if root.findtext('servervalidation/usepinnedroot', 'false').strip().lower() not in {'false', '0'}:
        raise ValueError('usepinnedroot profile policy is unsupported by this upstream version; no override is permitted')
    hosts = root.findall('serverlist/ServerEntry/fqdn')
    if len(hosts) != 1:
        raise ValueError('Exactly one gateway is required; review other profile shapes manually')
    host = (hosts[0].text or '').strip()
    if len(host) > 253 or not all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', x) for x in host.split('.')):
        raise ValueError('Invalid gateway hostname')
    transport = root.findtext('protocolconfig/sslprotocolConfig/transportprotocol', 'tcp')
    if transport.lower() != 'tcp':
        raise ValueError('Only TCP profiles are supported')
    fingerprint = root.findtext('servervalidation/Cert/hash', '')
    fingerprint = fingerprint.replace(':', '').replace(' ', '').lower()
    if not re.fullmatch('[0-9a-f]{40}', fingerprint):
        raise ValueError('Profile must identify a trusted root using its SHA-1 thumbprint')
    matches = []
    for pem in re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', bundle.read_text(), re.S):
        der = ssl.PEM_cert_to_DER_cert(pem)
        if hashlib.sha1(der).hexdigest() == fingerprint:
            matches.append(pem + '\n')
    matches = list(dict.fromkeys(matches))
    if len(matches) != 1:
        raise ValueError('Profile root not uniquely found in the existing trusted CA bundle; do not disable verification')
    output.mkdir(mode=0o700)
    ca = output / 'ca.pem'
    ca.write_text(matches[0])
    ca.chmod(0o600)
    # Require an actual trusted, currently valid, self-signed CA, not an arbitrary leaf.
    check = subprocess.run(['openssl', 'verify', '-check_ss_sig', '-CAfile', str(ca), str(ca)], capture_output=True)
    details = subprocess.run(['openssl', 'x509', '-in', str(ca), '-noout', '-text'], capture_output=True, text=True, check=True)
    subject = subprocess.check_output(['openssl', 'x509', '-in', str(ca), '-noout', '-subject', '-issuer'], text=True).splitlines()
    if check.returncode or 'CA:TRUE' not in details.stdout or subject[0].partition('=')[2] != subject[1].partition('=')[2]:
        raise ValueError('Matched certificate is not a valid self-signed CA root')
    dest = output / 'profile.xml'
    dest.write_bytes(raw)
    dest.chmod(0o600)
    return host
