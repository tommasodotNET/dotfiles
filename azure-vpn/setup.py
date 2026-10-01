#!/usr/bin/env python3
"""Opt-in installer. Does not authenticate, connect, use sudo, or modify system config."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile

from profile import prepare

REVISION = 'b6dc0216242d2adea643847ddd266e1bbc6730df'
REPOSITORY = 'https://github.com/wyruweso/openp2s.git'
RELEASE = 'https://github.com/wyruweso/openp2s/releases/download/v0.2.1/'
ARCHIVE = 'openp2s-0.2.1-linux-amd64.tar.gz'
ARCHIVE_SHA = '3877a670221906810bb13dcd7e714c9dda7cd9820e70c4240fc7d88ada0be676'
CLI_SHA = 'b2514247df882cd3e9bf12c869f9d8725580d701ac69744c01d317c24f97960c'
VPN_SHA = '8c00591c80bcc3498107a92784fcc07323b016e7b4b64ce651f615366d27ec7a'
TOPIC = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def absent(path):
    if path.exists() or path.is_symlink():
        raise ValueError(f'Refusing to overwrite existing destination: {path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path, help='Private Azure XML supplied separately; never store in dotfiles')
    parser.add_argument('--node', default=shutil.which('node'), help='Node 24.13+ absolute executable (default: current node)')
    parser.add_argument('--trust-bundle', type=Path, default=Path('/etc/pki/tls/certs/ca-bundle.crt'), help='Existing trusted CA bundle; Fedora default')
    args = parser.parse_args()
    if sys.version_info < (3, 12):
        raise ValueError('Python 3.12+ is required for safe archive extraction')
    if os.geteuid() == 0:
        raise ValueError('Run as the desktop user, not root or sudo')
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise ValueError('This pinned release is for Linux x86-64 only')
    home = Path.home()
    base = home / '.local/share/dotfiles-azure-vpn'
    launcher = home / '.local/bin/azure-vpn'
    desktop = home / '.local/share/applications/azure-vpn.desktop'
    for dest in [base, launcher, desktop]:
        absent(dest)
    # A surprising parent symlink must not redirect private outputs into a repository.
    for dest in [base, launcher, desktop]:
        if dest.parent.resolve() != dest.parent.absolute():
            raise ValueError('Destination parent uses a symlink; review layout manually')
    if not args.profile.is_file() or args.profile.is_symlink():
        raise ValueError('Supply an existing regular, non-symlink profile file')
    if args.profile.resolve().is_relative_to(TOPIC.parent):
        raise ValueError('The private profile must be stored outside the dotfiles repository')
    if not args.trust_bundle.is_file():
        raise ValueError('Trusted CA bundle not found')
    if not args.node:
        raise ValueError('Node 24.13+ required; run dotfiles node setup first')
    node = Path(args.node).resolve(strict=True)
    version = subprocess.check_output([str(node), '-p', 'process.versions.node'], text=True).strip()
    parts = tuple(map(int, version.split('.')))
    if not ((24, 13, 0) <= parts < (25, 0, 0)):
        raise ValueError('Use supported Node 24.13+ (24.x); other major versions are not validated')
    npm = node.parent / 'npm'
    if not npm.is_file():
        raise ValueError('npm must be installed beside the selected Node executable')
    for command in ['git', 'curl', 'gh', 'openssl', 'sha256sum', 'resolvectl', 'ip', 'sudo', 'systemctl']:
        if not shutil.which(command):
            raise ValueError(f'Missing prerequisite: {command}; install it separately')
    if subprocess.run(['systemctl', 'is-active', '--quiet', 'systemd-resolved']).returncode:
        raise ValueError('systemd-resolved must already be active; setup will not reconfigure DNS')
    os.umask(0o077)
    base.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.azure-vpn-setup-', dir=base.parent))
    try:
        payload = stage / 'payload'
        payload.mkdir(mode=0o700)
        host = prepare(args.profile, args.trust_bundle, payload / 'private')
        log = stage / 'setup.log'
        env = os.environ.copy()
        env['PATH'] = str(node.parent) + ':/usr/bin:/bin:/usr/sbin:/sbin'

        def run(command, cwd=None, public_test=False):
            with log.open('ab') as output:
                result = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=output,
                                        umask=0o022 if public_test else 0o077)
            if result.returncode:
                raise ValueError(f'{Path(command[0]).name} failed (exit {result.returncode}). A download, attestation, or validation command failed. No installation published. Check prerequisites/GitHub access and retry; no sign-in is performed by setup.')

        print('Preparing pinned public source and release; no VPN connection or sign-in.', flush=True)
        archive = stage / ARCHIVE
        run(['curl', '--fail', '--location', '--proto', '=https', '--tlsv1.2', '--retry', '3', RELEASE + ARCHIVE, '--output', str(archive)])
        if sha(archive) != ARCHIVE_SHA:
            raise ValueError('Release archive checksum mismatch')
        unpack = stage / 'unpack'
        unpack.mkdir()
        with tarfile.open(archive) as tar:
            # Reject links and special files even though the archive has a pinned digest.
            if any(not (m.isfile() or m.isdir()) for m in tar.getmembers()):
                raise ValueError('Unexpected release archive member')
            tar.extractall(unpack, filter='data')
        bundle = unpack / 'openp2s-0.2.1-linux-amd64'
        if sha(bundle / 'openp2s') != CLI_SHA or sha(bundle / 'openvpn-openp2s') != VPN_SHA:
            raise ValueError('Release binary checksum mismatch')
        run(['sha256sum', '--check', 'SHA256SUMS'], cwd=bundle)
        for binary in ['openp2s', 'openvpn-openp2s']:
            run(['gh', 'attestation', 'verify', str(bundle / binary), '--repo', 'wyruweso/openp2s',
                 '--bundle', str(TOPIC / 'attestations' / (binary + '.json')), '--source-digest', REVISION])
        shutil.move(str(bundle), payload / 'bundle')
        source = payload / 'source'
        run(['git', 'clone', '--no-checkout', REPOSITORY, str(source)])
        run(['git', 'checkout', '--detach', REVISION], cwd=source)
        run(['git', 'apply', '--check', str(TOPIC / 'openp2s-routes.patch')], cwd=source)
        run(['git', 'apply', str(TOPIC / 'openp2s-routes.patch')], cwd=source)
        run(['bash', 'scripts/verify-provenance.sh', '--binary', str(payload / 'bundle/openvpn-openp2s'), '--buildinfo', str(payload / 'bundle/BUILDINFO')], cwd=source)
        run([str(npm), 'ci', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=source)
        # Existing upstream security tests intentionally create permissive directories.
        # Only the test subprocess uses 022, never the private staging directories.
        run([str(npm), 'run', 'check'], cwd=source, public_test=True)
        # Validate the whole profile with the patched parser, not only the strict setup subset.
        # Swallow parser exceptions to prevent profile values appearing in an error log.
        script = "import {AzureProfileParser} from './src/profile/parser.ts'; import {readFileSync} from 'node:fs'; try { new AzureProfileParser().parse(readFileSync(process.argv[1], 'utf8')); } catch { process.exit(1); }"
        run([str(node), '--input-type=module', '-e', script, str(payload / 'private/profile.xml')], cwd=source)
        (payload / 'settings.json').write_text(json.dumps({'node': str(node), 'node_version': version, 'server_name': host}, indent=2) + '\n')
        shutil.copy2(TOPIC / 'launcher.py', payload / 'launcher.py')
        shutil.copy2(TOPIC / 'README.md', payload / 'README.md')
        shutil.copy2(log, payload / 'verification.log')
        # Record all installed source/dependency bytes, private config and public binaries.
        # Git metadata is not executable input and is deliberately excluded.
        manifest = {}
        for path in payload.rglob('*'):
            if path.is_file() and not path.is_symlink() and '.git' not in path.relative_to(payload).parts:
                manifest[str(path.relative_to(payload))] = sha(path)
        (payload / 'integrity.json').write_text(json.dumps(manifest, sort_keys=True) + '\n')
        for path in [payload / 'settings.json', payload / 'integrity.json']:
            path.chmod(0o600)
        # Recheck after slow downloads; never replace an install created in the meantime.
        for dest in [base, launcher, desktop]:
            absent(dest)
        for parent in [launcher.parent, desktop.parent]:
            parent.mkdir(parents=True, exist_ok=True)
        # Reserve the destination atomically. No existing installation is overwritten.
        base.mkdir(mode=0o700)
        for entry in payload.iterdir():
            shutil.move(str(entry), base / entry.name)
        with launcher.open('x') as stream:
            stream.write((TOPIC / 'launcher.py').read_text())
        launcher.chmod(0o700)
        # Exec follows Desktop Entry escaping, not shell quoting.
        executable = str(launcher).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
        with desktop.open('x') as stream:
            stream.write('[Desktop Entry]\nType=Application\nName=Azure VPN (OpenP2S trial)\nComment=Manual Microsoft Entra VPN; close with Ctrl+C\nTerminal=true\nIcon=network-vpn\nCategories=Network;\nExec="' + executable + '" connect\n')
        desktop.chmod(0o600)
        print('Setup validated and installed. No sign-in, tunnel, auto-start, or system changes performed.')
        print('Run ~/.local/bin/azure-vpn doctor, then deliberately run connect when ready.')
        print('Keep the terminal open; Ctrl+C disconnects. Read azure-vpn/README.md before use.')
    finally:
        shutil.rmtree(stage)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as error:
        # Expected setup errors are deliberately generic about profile content.
        print(f'Azure VPN setup stopped: {error}', file=sys.stderr)
        sys.exit(1)
