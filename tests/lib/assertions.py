#!/usr/bin/env python3
"""Assertions shared by fixture and real-index runs (Python 3.11+)."""
import json
from pathlib import Path
import sys
import tomllib

mode = sys.argv[1]
if mode == 'lock':
    lock, storage, version = Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
    data = tomllib.loads(lock.read_text())
    tool = data['tools']['flutter'][0]
    assert tool['version'] == version, tool
    platforms = {k.removeprefix('platforms.'): v for k, v in tool.items() if k.startswith('platforms.')}
    for platform in ('macos-arm64', 'macos-x64', 'linux-x64', 'windows-x64'):
        record = platforms[platform]
        os_name, arch = platform.split('-')
        index = json.loads((storage / f'flutter_infra_release/releases/releases_{os_name}.json').read_text())
        channel = 'beta' if version in ('beta', '9.9.10-0.1.pre') else 'stable'
        entry = next(e for e in index['releases'] if e['channel'] == channel and e['dart_sdk_arch'] == arch)
        assert record['url'].endswith('/' + entry['archive']), record
        assert record['checksum'] == 'sha256:' + entry['sha256'], record
elif mode == 'marker':
    root, source = Path(sys.argv[2]), sys.argv[3]
    marker = json.loads((root / '.mise-flutter.json').read_text())
    assert marker['schema'] == 1 and marker['source'] == source, marker
    if source == 'archive':
        assert len(marker['sha256']) == 64 and marker['version'] in ('9.9.9', '9.9.10-0.1.pre', '9.9.11'), marker
        assert marker['sha256'] == (root / '.mise.checksum').read_text().strip(), marker
    else:
        assert len(marker['framework_revision']) == 40 and 'sha256' not in marker, marker
    if len(sys.argv) > 4:
        assert marker['bootstrapped'] == (sys.argv[4] == 'true'), marker
elif mode == 'env':
    data = json.loads(Path(sys.argv[2]).read_text())
    version, bootstrapped = sys.argv[3:5]
    assert data['MISE_FLUTTER_DART_VERSION'] == version, data
    assert str(Path(data['FLUTTER_ROOT']) / 'bin').replace('\\', '/') in data['PATH'].replace('\\', '/'), data
    assert data['MISE_FLUTTER_CHANNEL'] == 'stable', data
    assert len(data['MISE_FLUTTER_REVISION']) == 40, data
    assert ('DART_SDK' in data) == (bootstrapped == 'true'), data
    if bootstrapped == 'true':
        assert Path(data['DART_SDK']).is_dir()
elif mode == 'real-lock':
    data = tomllib.loads(Path(sys.argv[2]).read_text())
    tool = data['tools']['flutter'][0]
    platforms = {k.removeprefix('platforms.'): v for k, v in tool.items() if k.startswith('platforms.')}
    assert set(platforms) >= {'macos-arm64', 'macos-x64', 'linux-x64', 'windows-x64'}
    for record in platforms.values():
        assert record['url'].startswith('https://storage.googleapis.com/flutter_infra_release/releases/')
        assert record['checksum'].startswith('sha256:') and len(record['checksum']) == 71
else:
    raise AssertionError(f'unknown assertion {mode}')
