# Implementation notes — v0.1.0

## Decisions and deviations

- **Windows arm64:** follows DESIGN §5.1/§5.2 (x64 under emulation, warning),
  not the contradictory rejection in §0. Native arm64 is not claimed.
- **Main snapshot ordering:** `Available` names snapshots
  `main-<UTC commit time>-<12 hex>` instead of `main-<12 hex>`. mise compares
  version strings, so a bare hash could make a newer commit look older. The
  timestamp prefix makes ordering monotonic without a fake checksum. The
  integration test installs three local commits and upgrades through them in
  both ascending and descending SHA order; `mise outdated` and `mise upgrade
  --dry-run` report each new snapshot. A pinned timestamp is validated against
  the commit's actual GitHub committer date, so a user cannot invent an
  ordering prefix. Old `main-<12 hex>` pins are still accepted for
  compatibility, but they do not participate in timestamped upgrades.
- **Main snapshots are undated:** `Available` deliberately omits `created_at`
  for `main-<timestamp>-<sha>` entries. mise's default `minimum_release_age`
  otherwise hides a commit made today, so `flutter@main` would resolve to the
  bare `main` fallback instead of the snapshot. The timestamp prefix provides
  string ordering without a release cooldown. Stable/beta/exact releases keep
  their real `release_date` and remain subject to the cooldown.
- **Main API-outage fallback:** §3.3 promises an API-outage fallback but §6.3
  requires API resolution. For literal `main` only, PreInstall can return no URL
  when the API fails. PostInstall uses `git ls-remote ... refs/heads/master`,
  fetches that full SHA, and verifies HEAD. This is API-independent, not offline:
  Git network access is still necessary. Snapshots and short commits fail closed.
- **Optional choices:** only `.flutter-version`; no `.fvmrc`. Satisfaction checks
  remain local and do not run Git. Tiny archives/indexes are deterministically
  generated in disposable `.tmp/` directories rather than committed binaries.
- **Testing mechanics:** API stubs use mise `url_replacements`; local Git uses
  an isolated Git `insteadOf` configuration. There are no test endpoints or
  arbitrary Git-repository options in the plugin. Lua unit assertions run via
  a temporary plugin copy under mise; no Lua interpreter dependency or debug
  hook is shipped. Python 3.11+ is required for fixture/lockfile tests.
- **Additional modules:** `catalog`, `resolver`, and `environment` keep hooks
  thin. Do not name a library `available`: mise's require search finds
  `hooks/available.lua` before `lib/available.lua`.

## Known limitations

- **Rolling channels and `--locked`:** with mise 2026.11.4, `mise install
  --locked` can re-resolve `stable`/`beta` against the current release index.
  The lockfile still stores the per-platform URL and checksum, but a changed
  channel may install a different release than the one recorded. Use an exact
  version when strict byte pinning matters. This is a mise behavior, not a
  plugin workaround; the integration test documents it.
- **`mise lock` downloads archives:** on mise 2026.11.4, `mise lock
  --platform` hashes each platform's archive itself instead of trusting the
  `PreInstall` checksum. Pinning four platforms can download several GB. The
  plugin cannot prevent this; `tests/real-index.sh` blocks the archive URLs and
  treats the attempted GETs as a known limitation. Users should generate
  lockfiles with bandwidth/disk in mind, lock one platform, or rely on install
  verification.
- **Git-only installs and lockfiles:** `main` snapshots and unreleased commits
  have no artifact URL or checksum, so locked mode cannot verify their bytes.
  The commit SHA in the version string is the pin. Use `git-<sha>` for a
  published release when a lockable, checksummed install is required.
- **Windows arm64:** there is no native Flutter Windows arm64 SDK. The plugin
  selects the x64 archive under Windows emulation and logs a warning. This is
  best effort and is exercised by the CI fixture matrix, not by a native
  arm64 Windows runner.
- **No engine artifact pre-cache:** `bootstrap = true` provisions the Dart SDK
  and Flutter tool, not Android/iOS/web engine artifacts. Run `flutter
  precache` for those.

## Verification status (2026-11-10)

- `bash tests/integration.sh` passed locally on macOS arm64 with mise 2026.11.4.
  It covers resolution, official checksum enforcement, stable/beta channel
  upgrades, exact versions, released and unreleased commits, main snapshots in
  both hash orders, `.flutter-version`, environment keys, repair, lockfiles,
  prune, and paths containing spaces/parentheses.
- `bash tests/real-index.sh` could not complete in this environment on the
  final run: `curl` to `storage.googleapis.com` failed with a TLS connection
  reset. A real `mise ls-remote flutter` against
  `https://storage.flutter-io.cn` (mirror) returned 238 versions including
  `stable`, `beta`, and one `main-<timestamp>-<sha>` entry; `mise latest`
  returned `3.47.9`, and `mise install flutter@main --dry-run` resolved to the
  snapshot with the default release-age setting. The fixture tests and CI
  `real-index` job cover the same code paths without relying on this network.
- An unguarded real `mise lock --platform ...` was not completed: mise tried to
  download each platform's SDK archive, confirming the known limitation
  documented above. The fixture lock tests cover URL/checksum selection.
- `bash tests/real-install.sh` was not run locally; it downloads a multi-GB
  SDK and is reserved for the nightly/manual CI job.
- `mise run lint` passed locally with the pinned `stylua` 2.3.1, `actionlint`
  1.7.7 and `shellcheck` 0.11.0 installed in an isolated mise data directory.

## Local acceptance record

Host: macOS arm64; mise 2026.11.4. All mise commands used repository-local
`.tmp/` configuration, data, cache, state, system and global-config paths.

- T0: link/list/cache-clear passed.
- T1: request/hex/path/platform/checksum Lua assertions passed through mise.
- T2: fixture and real listing passed (`3.47.9`, stable); API outage preserves
  archives; index HTTP 404 fails clearly.
- T3: stable, beta, exact and exact prerelease lock across macOS arm64/x64,
  Linux x64 and Windows x64 passed; missing checksum rejected.
- T4: archive install, marker, repeat install and missing executable passed.
- T5: marker Dart version, actual version-file override, DART_SDK existence,
  environment cache invalidation and fixture executable passed.
- T6: released commit uses archive; short/full unreleased local Git installs,
  HEAD verification, missing-Git and mismatched-HEAD failures passed.
  Real shallow fetch of `c197ca5199e9ee5661e865596c9c07294dfab51c` took 65 s
  and 223 MB, then was removed. No Flutter invocation, SDK archive or Dart
  bootstrap download was made.
- T7: snapshot resolution/install and API failure passed. The timestamp-prefixed
  grammar fixes the earlier hash-ordering problem; both ascending and
  descending SHA upgrade directions pass the fixture test.

Linux/Windows execution and real SDK bootstrap require the supplied CI matrix
and nightly/manual jobs; they cannot be claimed green from this macOS checkout.
