#!/usr/bin/python3
"""Manual launcher; configuration and profiles remain outside the dotfiles repo."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

COMMANDS = {'connect', 'login', 'doctor', 'status', 'disconnect'}
if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
    print('Usage: azure-vpn {connect|login|doctor|status|disconnect}')
    sys.exit(0 if len(sys.argv) == 2 and sys.argv[1] in {'--help', '-h'} else 2)
if os.geteuid() == 0:
    sys.exit('Run as your desktop user, not with sudo.')
os.umask(0o077)
os.environ['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin'
base = Path.home() / '.local/share/dotfiles-azure-vpn'
try:
    config = json.loads((base / 'settings.json').read_text())
    manifest = json.loads((base / 'integrity.json').read_text())
    for relative, expected in manifest.items():
        path = base / relative
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Installed files changed; review and rebuild the installation')
    node = config['node']
    version = subprocess.check_output([node, '-p', 'process.versions.node'], text=True).strip()
    if version != config['node_version']:
        raise ValueError('Node version changed; review and rebuild before connecting')
except (OSError, ValueError, KeyError, subprocess.CalledProcessError):
    sys.exit('Azure VPN installation missing or changed. Review setup; refusing to run.')
os.environ['OPENP2S_OPENVPN_BINARY'] = str(base / 'bundle/openvpn-openp2s')
cli = [node, str(base / 'source/src/cli/run.ts')]
profile = str(base / 'private/profile.xml')
ca = str(base / 'private/ca.pem')
client = 'c632b3df-fb67-4d84-bdcf-b95ad541b5c8'
command = sys.argv[1]
if command == 'connect':
    print('Manual Azure VPN: use the local sudo prompt; Ctrl+C disconnects.', flush=True)
    subprocess.run(['/usr/bin/sudo', '-v'], check=True)
    args = ['connect', profile, '--auth', 'browser', '--client-id', client,
            '--ca', ca, '--verify-name', config['server_name'],
            '--experimental-azure-compat', '--openvpn-binary',
            str(base / 'bundle/openvpn-openp2s')]
elif command == 'login':
    args = ['auth', 'login', profile, '--auth', 'browser', '--client-id', client]
elif command == 'doctor':
    args = ['doctor', profile, '--ca', ca]
else:
    args = [command]
os.execv(node, cli + args)
