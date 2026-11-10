#!/usr/bin/env python3
"""Build ascending then descending hashes with increasing commit timestamps."""
import json
import os
from pathlib import Path
import subprocess
import sys

root, storage, config = map(Path, sys.argv[1:])
root.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
           GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
           GIT_AUTHOR_DATE='2020-01-01T00:00:00Z', GIT_COMMITTER_DATE='2020-01-01T00:00:00Z')


def git(*args, data=None):
    return subprocess.check_output(['git', *args], cwd=root, env=env, input=data).decode().strip()


git('init', '-q')
(root / 'bin').mkdir(exist_ok=True)
for p in (Path(__file__).parent / 'archive').iterdir():
    out = root / 'bin' / p.name
    out.write_bytes(p.read_bytes())
    out.chmod(0o755)
git('add', 'bin')
git('update-index', '--chmod=+x', 'bin/flutter', 'bin/dart')
tree = git('write-tree')
first = git('commit-tree', tree, data=b'Fixture one\n')
commits = [first]
for day in (2, 3):
    env['GIT_AUTHOR_DATE'] = env['GIT_COMMITTER_DATE'] = f'2020-01-0{day}T00:00:00Z'
    for attempt in range(10000):
        candidate = git('commit-tree', tree, '-p', commits[-1], data=f'Fixture {day} {attempt}\n'.encode())
        if (day == 2 and candidate > commits[-1]) or (day == 3 and candidate < commits[-1]):
            commits.append(candidate)
            break
    else:
        raise AssertionError('could not generate ordered fixture commits')
git('update-ref', 'refs/heads/master', commits[-1])
git('symbolic-ref', 'HEAD', 'refs/heads/master')
api = storage / 'api/repos/flutter/flutter/commits'
for day, sha in enumerate(commits, 1):
    record = dict(sha=sha, commit=dict(committer=dict(date=f'2020-01-0{day}T00:00:00Z')))
    for ref in (sha[:7], sha[:12]):
        (api / ref).write_text(json.dumps(record))
(api / 'master').write_text((api / first[:12]).read_text())
(root / 'commits.json').write_text(json.dumps(commits))
subprocess.check_call(['git', 'config', '--file', str(config),
                       f'url.{root.resolve().as_uri()}.insteadOf', 'https://github.com/flutter/flutter.git'])
