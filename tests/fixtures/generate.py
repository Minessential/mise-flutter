#!/usr/bin/env python3
"""Deterministic tiny archives and indexes. Output belongs in a disposable test dir."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import zipfile

STABLE = 'a' * 40
BETA = 'b' * 40
SOURCE = Path(__file__).parent / 'archive'


def archive(path, arch, missing=False, version='9.9.9', sha=STABLE, windows=False):
    files = {f'flutter/bin/{p.name}': p.read_bytes().replace(b'9.9.9', version.encode()).replace(STABLE.encode(), sha.encode())
             for p in sorted(SOURCE.iterdir())}
    files['flutter/fixture-arch'] = arch.encode()
    # Windows must exercise .bat-only discovery, not POSIX wrappers.
    if windows:
        del files['flutter/bin/flutter']
        del files['flutter/bin/dart']
    if missing:
        files.pop('flutter/bin/flutter', None)
        del files['flutter/bin/flutter.bat']
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == '.zip':
        with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as out:
            for name, data in files.items():
                info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100755 << 16
                out.writestr(info, data)
    else:
        with tarfile.open(path, 'w:xz') as out:
            for name, data in files.items():
                info = tarfile.TarInfo(name)
                info.size, info.mode, info.mtime = len(data), 0o755, 0
                out.addfile(info, io.BytesIO(data))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(root):
    for variant in ('good', 'tampered', 'missing', 'no-checksum', 'updated'):
        dest = root / variant / 'flutter_infra_release/releases'
        for os_name in ('macos', 'linux', 'windows'):
            entries = []
            stable = '9.9.11' if variant == 'updated' else '9.9.9'
            stable_sha = 'e' * 40 if variant == 'updated' else STABLE
            for channel, version, sha in (('beta', '9.9.10-0.1.pre', BETA), ('stable', stable, stable_sha)):
                for arch in (('x64', 'arm64') if os_name == 'macos' else ('x64',)):
                    suffix = 'tar.xz' if os_name == 'linux' else 'zip'
                    name = f'{channel}/{os_name}/flutter_{os_name}_{arch}_{version}-{channel}.{suffix}'
                    checksum = archive(dest / name, arch, missing=variant == 'missing',
                                       version=version, sha=sha, windows=os_name == 'windows')
                    entry = dict(version=version, hash=sha, channel=channel, archive=name,
                                 sha256=checksum, dart_sdk_arch=arch, dart_sdk_version='7.7.7',
                                 release_date='2020-01-01T00:00:00Z')
                    if variant == 'tampered':
                        entry['sha256'] = '0' * 64
                    if variant == 'no-checksum':
                        del entry['sha256']
                    entries.append(entry)
            entries.append(dict(entries[-1], channel='dev', version='8.0.0-dev'))
            data = dict(base_url='https://ignored.invalid', current_release=dict(stable=stable_sha, beta=BETA), releases=entries)
            (dest / f'releases_{os_name}.json').write_text(json.dumps(data, indent=2) + '\n')
    api = root / 'api/repos/flutter/flutter/commits'
    api.mkdir(parents=True, exist_ok=True)
    main = 'c' * 40
    data = dict(sha=main, commit=dict(committer=dict(date='2020-01-02T00:00:00Z')))
    for ref in ('master', main[:12], main[:7]):
        (api / ref).write_text(json.dumps(data))
    for sha in (STABLE, BETA):
        (api / sha[:7]).write_text(json.dumps(dict(data, sha=sha)))


if __name__ == '__main__':
    generate(Path(sys.argv[1]))
