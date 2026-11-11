#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
export REPO
mkdir -p "$REPO/.tmp"
TEST_DIR=$(mktemp -d "$REPO/.tmp/fixture.XXXXXX")
# shellcheck source=tests/lib/isolate.sh
source "$REPO/tests/lib/isolate.sh" "$TEST_DIR"
source "$REPO/tests/lib/python.sh"
server_pid=
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_failure() {
  local message=$1; shift
  if "$@" > "$TEST_DIR/error" 2>&1; then fail "unexpected success: $*"; fi
  grep -Fiq "$message" "$TEST_DIR/error" || { tail -30 "$TEST_DIR/error"; fail "missing error: $message"; }
}
assert_py() { "$PYTHON" "$REPO/tests/lib/assertions.py" "$@"; }
head_of() { git -C "$1" rev-parse HEAD | tr -d '\r\n'; }
project() {
  rm -f mise.lock
  printf '[tools]\nflutter = { version = "%s", bootstrap = %s }\n' "$1" "${2:-false}" > mise.toml
}

"$PYTHON" "$REPO/tests/fixtures/generate.py" "$TEST_DIR/storage"
"$PYTHON" "$REPO/tests/fixtures/server.py" "$TEST_DIR/storage" "$TEST_DIR/port" "$TEST_DIR/requests" &
server_pid=$!
for _ in {1..300}; do [[ -s "$TEST_DIR/port" ]] && break; sleep .1; done
[[ -s "$TEST_DIR/port" ]] || fail 'fixture server did not start'
port=$(<"$TEST_DIR/port")
export FLUTTER_STORAGE_BASE_URL="http://127.0.0.1:$port/good"
export MISE_URL_REPLACEMENTS="{\"https://api.github.com/\":\"http://127.0.0.1:$port/api/\"}"
mkdir -p "$TEST_DIR/project"
cd "$TEST_DIR/project"
mise plugins link flutter "$REPO"

# Run pure Lua assertions through mise's actual Lua runtime, in a disposable copy.
mkdir -p "$TEST_DIR/unit/hooks" "$TEST_DIR/unit/lib"
cp "$REPO/metadata.lua" "$TEST_DIR/unit/"
cp "$REPO"/lib/*.lua "$REPO/tests/unit.lua" "$TEST_DIR/unit/lib/"
printf 'function PLUGIN:Available(ctx) return require("unit").run() end\n' > "$TEST_DIR/unit/hooks/available.lua"
mise plugins link --force flutter "$TEST_DIR/unit"
mise ls-remote flutter > "$TEST_DIR/unit-result"
grep -qx 9.9.9 "$TEST_DIR/unit-result"
mise plugins link --force flutter "$REPO"
mise cache clear flutter

mise ls-remote flutter > versions
for v in stable beta 9.9.9 main-20200102000000-cccccccccccc; do grep -qx "$v" versions; done
if grep -q dev versions; then fail 'dev release was listed'; fi
# Main snapshots are undated, so a release-age cutoff must not hide them.
MISE_MINIMUM_RELEASE_AGE=876000h mise ls-remote flutter > versions-age
grep -q '^main-' versions-age
[[ $(mise latest flutter) = 9.9.9 ]]
project stable
mise install
root="$MISE_DATA_DIR/installs/flutter/stable"
assert_py marker "$root" archive false
[[ ! -e "$root/bootstrap-calls" ]]
mise install
mise exec -- flutter --version > flutter-version
grep -q 'Flutter fixture 9.9.9' flutter-version
mise exec -- dart --version > dart-version
grep -q '7.7.8' dart-version
export MISE_ENV_CACHE=1
mise env --json > environment
assert_py env environment 7.7.7 false
mkdir -p "$root/bin/cache/dart-sdk"
printf '7.7.9\n' > "$root/bin/cache/dart-sdk/version"
mise env --json > environment
assert_py env environment 7.7.9 true
rm -rf "$root/bin/cache/dart-sdk"

# Repair options in place; prove no second archive request.
before=$(grep -Ec 'GET .*\.(zip|xz)' "$TEST_DIR/requests")
project stable true
mise install
after=$(grep -Ec 'GET .*\.(zip|xz)' "$TEST_DIR/requests")
[[ "$before" = "$after" ]]
assert_py marker "$root" archive true
mise env --json > environment
assert_py env environment 7.7.8 true
# flutter.version.json wins over the expected marker even without a Dart tree.
rm -rf "$root/bin/cache/dart-sdk"
mise env --json > environment
assert_py env environment 7.7.8 false
expect_failure 'bootstrap = false' env FIXTURE_BOOTSTRAP_FAIL=1 mise install
grep -q 'fixture bootstrap failed' "$TEST_DIR/error"
assert_py marker "$root" archive false
mise install

project stable false
mise install flutter@9.9.10-0.1.pre
mise install flutter@git-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mise install flutter@git-aaaaaaa
assert_py marker "$MISE_DATA_DIR/installs/flutter/git-aaaaaaa" archive false
for version in stable beta 9.9.9 9.9.10-0.1.pre git-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; do
  project "$version"
  mise lock --platform macos-arm64,macos-x64,linux-x64,windows-x64
  assert_py lock mise.lock "$TEST_DIR/storage/good" "$version"
done
# Channel checksums change independently of the literal version name.
project stable
cp -R "$TEST_DIR/storage/good" "$TEST_DIR/storage/original"
cp -R "$TEST_DIR/storage/updated/." "$TEST_DIR/storage/good/"
mise cache clear flutter
mise outdated > outdated.txt
grep -q stable outdated.txt
mise upgrade flutter
assert_py marker "$root" archive false
mise exec -- flutter --version | grep -q '9.9.11'
# Lock the new stable, restore the old index, and measure locked-mode behavior.
mise lock --platform macos-arm64,macos-x64,linux-x64,windows-x64
cp -R "$TEST_DIR/storage/original/." "$TEST_DIR/storage/good/"
mise uninstall flutter@stable
mise cache clear flutter
mise install --locked
mise exec -- flutter --version > locked-version
if grep -q '9.9.9' locked-version; then
  echo 'KNOWN mise limitation: --locked re-resolves rolling channel from current index'
else
  grep -q '9.9.11' locked-version
fi
project 9.9.9
mise lock --platform macos-arm64,macos-x64,linux-x64,windows-x64
mise install --locked
assert_py marker "$MISE_DATA_DIR/installs/flutter/9.9.9" archive false
mise uninstall flutter@9.9.9
rm -f mise.lock
expect_failure 'checksum' env FLUTTER_STORAGE_BASE_URL="http://127.0.0.1:$port/tampered" mise install flutter@9.9.9
[[ ! -e "$MISE_DATA_DIR/installs/flutter/9.9.9/bin/flutter" ]]
expect_failure 'did not contain bin/flutter' env FLUTTER_STORAGE_BASE_URL="http://127.0.0.1:$port/missing" mise install flutter@9.9.9
case "$(uname -s)" in MINGW*|MSYS*) grep -q 'antivirus quarantine' "$TEST_DIR/error" ;; esac
expect_failure 'no sha256' env FLUTTER_STORAGE_BASE_URL="http://127.0.0.1:$port/no-checksum" mise install flutter@9.9.9
# mise lock reports an unsupported target as a warning and omits it on some versions.
mise lock --platform linux-arm64 > "$TEST_DIR/arm64" 2>&1 || true
grep -q 'Linux arm64' "$TEST_DIR/arm64"
if [[ -f mise.lock ]] && grep -q 'linux-arm64' mise.lock; then fail 'unsupported target locked'; fi
rm -f mise.lock
expect_failure 'obsolete' mise install flutter@dev
expect_failure 'hexadecimal' mise install flutter@git-abc
expect_failure 'HTTP 404' env FLUTTER_STORAGE_BASE_URL="http://127.0.0.1:$port/absent" mise install flutter@9.9.9

# Real local commits: later timestamps, first ascending then descending SHA order.
"$PYTHON" "$REPO/tests/fixtures/git_repo.py" "$TEST_DIR/git" "$TEST_DIR/storage" "$GIT_CONFIG_GLOBAL"
read -r first second third < <("$PYTHON" -c 'import json,sys; print(*json.load(open(sys.argv[1])))' "$TEST_DIR/git/commits.json")
first=${first%$'\r'}
second=${second%$'\r'}
third=${third%$'\r'}
mise install "flutter@git-${first:0:7}" "flutter@git-$third"
[[ $(head_of "$MISE_DATA_DIR/installs/flutter/git-${first:0:7}") = "$first" ]]
assert_py marker "$MISE_DATA_DIR/installs/flutter/git-${first:0:7}" git false
api="$TEST_DIR/storage/api/repos/flutter/flutter/commits"
snapshots=("main-20200101000000-${first:0:12}" "main-20200102000000-${second:0:12}" "main-20200103000000-${third:0:12}")
project main
mise cache clear flutter
mise install
[[ $(head_of "$MISE_DATA_DIR/installs/flutter/${snapshots[0]}") = "$first" ]]
for i in 1 2; do
  snapshot=${snapshots[$i]}
  cp "$api/${snapshot##*-}" "$api/master"
  mise cache clear flutter
  mise outdated > outdated.txt
  mise upgrade --dry-run > upgrade.txt 2>&1
  grep -q "$snapshot" outdated.txt
  grep -q "$snapshot" upgrade.txt
  mise upgrade flutter
  assert_py marker "$MISE_DATA_DIR/installs/flutter/$snapshot" git false
  expected=$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))[int(sys.argv[2])])' "$TEST_DIR/git/commits.json" "$i" | tr -d '\r\n')
  [[ $(head_of "$MISE_DATA_DIR/installs/flutter/$snapshot") = "$expected" ]]
done
expect_failure 'timestamp does not match' mise install "flutter@main-20200104000000-${third:0:12}"
# Old undated pins remain valid, but only dated snapshots participate in upgrades.
mise install "flutter@main-${first:0:12}"
rm "$MISE_DATA_DIR/installs/flutter/${snapshots[2]}/.mise-flutter.json"
mise install "flutter@${snapshots[2]}"
assert_py marker "$MISE_DATA_DIR/installs/flutter/${snapshots[2]}" git false

mise cache clear flutter
export MISE_URL_REPLACEMENTS="{\"https://api.github.com/\":\"http://127.0.0.1:$port/absent/\"}"
mise ls-remote flutter > versions
grep -qx stable versions
if grep -q main- versions; then fail 'unavailable main snapshot listed'; fi
# Remove snapshots so mise's installed-prefix resolution cannot mask fallback.
mise uninstall "flutter@${snapshots[0]}" "flutter@${snapshots[1]}" "flutter@${snapshots[2]}" "flutter@main-${first:0:12}"
# Simulate a stale cache from a preceding API-resolved main install.
mkdir -p "$MISE_CACHE_DIR/plugins/flutter"
printf '{"sha":"%s"}\n' "$first" > "$MISE_CACHE_DIR/plugins/flutter/commit-master.json"
mise install flutter@main
assert_py marker "$MISE_DATA_DIR/installs/flutter/main" git false
[[ $(head_of "$MISE_DATA_DIR/installs/flutter/main") = "$third" ]]
expect_failure 'HTTP 404' mise install flutter@git-ddddddd

# Legacy file opt-in, force, prune and space/parenthesis-safe cwd handling.
project stable
printf '\n  stable  \n' > .flutter-version
printf '[settings]\nidiomatic_version_file_enable_tools = ["flutter"]\n' > mise.toml
mise current flutter | grep -qx stable
rm .flutter-version
project stable
mise install --force flutter@stable
mise prune --dry-run > prune.txt
mise prune
[[ ! -d "$MISE_DATA_DIR/installs/flutter/git-$third" ]]
mise uninstall flutter@stable
export MISE_DATA_DIR="$TEST_DIR/data dir (spaces)"
mise plugins link flutter "$REPO"
project stable true
mise install
mise exec -- flutter --version > flutter-version
mise exec -- dart --version > dart-version
grep -q 'Flutter fixture 9.9.9' flutter-version
grep -q '7.7.8' dart-version
assert_py marker "$MISE_DATA_DIR/installs/flutter/stable" archive true
mise install "flutter@git-$third"
[[ $(head_of "$MISE_DATA_DIR/installs/flutter/git-$third") = "$third" ]]
mise uninstall flutter@stable "flutter@git-$third"
printf '\nPASS: fixture integration (resolution, checksums, Git, env, repair, locks, paths)\n'
