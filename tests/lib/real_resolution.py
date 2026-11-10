#!/usr/bin/env python3
"""Assert production hook output against each official index, without SDK GETs."""
import json
from pathlib import Path
import subprocess
import sys

cache, request = Path(sys.argv[1]), sys.argv[2]
base = 'https://storage.googleapis.com/flutter_infra_release/releases/'
for os_name, arch in (('darwin', 'arm64'), ('darwin', 'amd64'), ('linux', 'amd64'), ('windows', 'amd64')):
    result = json.loads((cache / f'resolution-{os_name}-{arch}.json').read_text())
    assert result['version'] == request
    index_os = 'macos' if os_name == 'darwin' else os_name
    # curl uses the host trust store even on Python.org macOS installations
    # whose optional CA bundle was not installed. Never disable TLS validation.
    index = json.loads(subprocess.check_output([
        'curl', '--fail', '--silent', '--show-error', '--retry', '2', '--max-time', '60',
        base + f'releases_{index_os}.json',
    ]))
    entry = next(e for e in index['releases'] if base + e['archive'] == result['url'])
    assert entry['sha256'] == result['sha256'] and len(result['sha256']) == 64
    assert entry.get('dart_sdk_arch', 'x64') == ('x64' if arch == 'amd64' else arch)
    if request in ('stable', 'beta'):
        assert entry['hash'] == index['current_release'][request] and entry['channel'] == request
    elif request.startswith('git-'):
        assert entry['hash'] == request[4:]
    else:
        assert entry['version'] == request
