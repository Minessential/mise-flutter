#!/usr/bin/env bash
# Explicit L3 opt-in: downloads a multi-GB SDK. Only nightly/manual CI calls this.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
export REPO
bootstrap=${1:-false}
[[ "$bootstrap" = true || "$bootstrap" = false ]]
TEST_DIR="$REPO/.tmp/real-install-$bootstrap"
# shellcheck source=tests/lib/isolate.sh
source "$REPO/tests/lib/isolate.sh" "$TEST_DIR"
source "$REPO/tests/lib/python.sh"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
mkdir -p "$TEST_DIR/project" "$TEST_DIR/home" "$TEST_DIR/pub-cache"
export HOME="$TEST_DIR/home" USERPROFILE="$TEST_DIR/home"
export XDG_CONFIG_HOME="$TEST_DIR/home/.config" APPDATA="$TEST_DIR/home/.appdata"
export LOCALAPPDATA="$TEST_DIR/home/.local-appdata"
export PUB_CACHE="$TEST_DIR/pub-cache"
cd "$TEST_DIR/project"
printf '[tools]\nflutter = { version = "3.47.9", bootstrap = %s }\n' "$bootstrap" > mise.toml
mise plugins link --force flutter "$REPO"
start=$SECONDS
mise install
mise exec -- flutter --suppress-analytics --version > version
grep -q 3.47.9 version
# Flutter's first invocation can print bootstrap progress before its JSON.
mise exec -- flutter --suppress-analytics --version --machine > machine.json
mise exec -- dart --version > dart-version 2>&1
mise which flutter > which-flutter
mise where flutter > where.txt
mise env --json > environment
"$PYTHON" - "$MISE_DATA_DIR" "$bootstrap" <<'PY'
import json
from pathlib import Path
import sys
root = Path(Path('where.txt').read_text().strip()).resolve()
data = Path(sys.argv[1]).resolve()
assert root.is_relative_to(data)
assert Path(Path('which-flutter').read_text().strip()).resolve().is_relative_to(root)
machine = json.loads(Path('machine.json').read_text())
assert machine['frameworkVersion'] == '3.47.9' and len(machine['frameworkRevision']) == 40
assert machine['dartSdkVersion'].split()[0] in Path('dart-version').read_text()
marker = json.loads((root / '.mise-flutter.json').read_text())
assert marker['bootstrapped'] == (sys.argv[2] == 'true')
assert (root / 'bin/cache/dart-sdk/version').is_file()
env = json.loads(Path('environment').read_text())
assert Path(env['DART_SDK']).is_dir()
assert env['MISE_FLUTTER_DART_VERSION'].split()[0] in Path('dart-version').read_text()
PY
if [[ $(uname -s) = Darwin ]]; then
  root=$(<where.txt)
  file "$root/bin/cache/dart-sdk/bin/dart" > architecture
  case "$(uname -m)" in arm64) grep -q arm64 architecture ;; *) grep -q x86_64 architecture ;; esac
fi
printf 'Real SDK acceptance: %ss\n' "$((SECONDS-start))"
du -sh "$MISE_DATA_DIR" "$MISE_CACHE_DIR"
