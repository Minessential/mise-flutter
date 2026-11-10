#!/usr/bin/env bash
# Resolution only. Block archives even if mise attempts to hash them while locking.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
export REPO
mkdir -p "$REPO/.tmp"
TEST_DIR=$(mktemp -d "$REPO/.tmp/real-index.XXXXXX")
# shellcheck source=tests/lib/isolate.sh
source "$REPO/tests/lib/isolate.sh" "$TEST_DIR"
source "$REPO/tests/lib/python.sh"
# Live metadata can be transiently unavailable; fixture tests keep retries off.
export MISE_HTTP_RETRIES=2
server_pid=
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
mkdir -p "$TEST_DIR/project" "$TEST_DIR/probe/hooks" "$TEST_DIR/empty"
"$PYTHON" "$REPO/tests/fixtures/server.py" "$TEST_DIR/empty" "$TEST_DIR/port" "$TEST_DIR/requests" &
server_pid=$!
for _ in {1..300}; do [[ -s "$TEST_DIR/port" ]] && break; sleep .1; done
[[ -s "$TEST_DIR/port" ]] || { echo 'download guard did not start' >&2; exit 1; }
port=$(<"$TEST_DIR/port")
touch "$TEST_DIR/requests"
cd "$TEST_DIR/project"
mise plugins link flutter "$REPO"
mise ls-remote flutter > versions
grep -qx 3.47.9 versions
grep -qx stable versions
mise latest flutter > latest.txt
grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' latest.txt

# A disposable observer records production PreInstall output on mise's target
# runtime. This is not shipped with the plugin and does not modify its result.
cp "$REPO/metadata.lua" "$TEST_DIR/probe/"
cp -R "$REPO/lib" "$TEST_DIR/probe/"
cp "$REPO"/hooks/*.lua "$TEST_DIR/probe/hooks/"
printf '%s\n' \
  'function PLUGIN:PreInstall(ctx)' \
  '  local result = require("resolver").pre_install(ctx)' \
  '  local path = require("file").join_path(RUNTIME.cacheDirPath, "resolution-" .. RUNTIME.osType .. "-" .. RUNTIME.archType .. ".json")' \
  '  require("flutter").write_json(path, result)' \
  '  return result' \
  'end' > "$TEST_DIR/probe/hooks/pre_install.lua"
mise plugins link --force flutter "$TEST_DIR/probe"
MISE_URL_REPLACEMENTS=$(printf '{"regex:^https://storage\\\\.googleapis\\\\.com/flutter_infra_release/releases/.+\\\\.(zip|tar\\\\.xz)$":"http://127.0.0.1:%s/SDK-DOWNLOAD-BLOCKED"}' "$port")
export MISE_URL_REPLACEMENTS
for version in 3.47.9 stable beta git-c197ca5199e9ee5661e865596c9c07294dfab51c; do
  printf '[tools]\nflutter = { version = "%s", bootstrap = false }\n' "$version" > mise.toml
  rm -f mise.lock "$MISE_CACHE_DIR"/plugins/flutter/resolution-*.json
  before=$(grep -c 'GET /SDK-DOWNLOAD-BLOCKED' "$TEST_DIR/requests" || true)
  mise lock --platform macos-arm64,macos-x64,linux-x64,windows-x64 > lock-output 2>&1 || true
  after=$(grep -c 'GET /SDK-DOWNLOAD-BLOCKED' "$TEST_DIR/requests" || true)
  "$PYTHON" "$REPO/tests/lib/real_resolution.py" "$MISE_CACHE_DIR/plugins/flutter" "$version"
  # Future mise versions may preserve hook checksums and complete without GETs.
  if [[ "$after" -gt "$before" ]]; then
    [[ $((after-before)) -eq 4 ]] || { tail -40 lock-output; exit 1; }
    echo "KNOWN mise limitation ($version): lock ignores hook checksum; four SDK GETs blocked"
  else
    "$PYTHON" "$REPO/tests/lib/assertions.py" real-lock mise.lock
  fi
done
mise install flutter@3.47.9 --dry-run
printf '\nPASS: real cross-platform PreInstall URLs/checksums (SDK transfers blocked)\n'
