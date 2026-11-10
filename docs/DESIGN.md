# mise-flutter — Development Specification

Status: implementation-ready
Target release: `v0.1.0`
Last updated: 2026-11-10
Implementer: pi
Companion research: [`RESEARCH.md`](./RESEARCH.md)

---

## 0. Decision summary

Build **one Lua tool plugin** named `flutter`, distributed from a GitHub
repository and installed with `[plugins]` / `mise plugins install`.

- **Channels**: `stable` and `beta` are rolling channel directories backed by
  official archives. `main` is exposed as immutable `main-<12-hex>` snapshots
  resolved from `flutter/flutter` and installed with Git.
- **Exact versions**: any stable/beta release published in the official release
  index, e.g. `3.47.9` or `3.50.0-0.4.pre`.
- **Commits**: `git-<7..40 hex>`. If the commit is a published release, install
  the official archive and verify its official SHA-256. Otherwise install a
  shallow Git checkout and verify the checked-out commit.
- **Integrity**: official archives always carry the `sha256` from
  `releases_<os>.json`; mise verifies it before extraction. Git installs are
  content-addressed by commit and verified with `git rev-parse HEAD`.
- **Dart**: Flutter's bundled Dart is exposed on `PATH` via `<root>/bin`; the
  plugin detects and exposes the Dart version without installing a second Dart
  SDK. A `bootstrap` option can pre-download the Dart SDK at install time.
- **Platforms**: macOS (x64 and arm64), Linux (x64), Windows (x64). Linux and
  Windows arm64 are rejected with an actionable message.
- **One implementation**: a single classifier and a single release resolver
  decide between two artifact providers (official archive, Git checkout). There
  is no second, parallel install script.

This document is the contract for implementation. If an implementation detail
conflicts with this document, stop and record the conflict in
`docs/IMPLEMENTATION-NOTES.md` rather than silently diverging.

---

## 1. Goals and acceptance criteria

| ID | Requirement | Acceptance |
| --- | --- | --- |
| R1 | Stable support | `mise use flutter@stable`, `mise exec -- flutter --version` prints the current stable version; `mise upgrade` follows the channel |
| R2 | Beta support | `mise use flutter@beta` installs the current beta; exact prerelease installs work |
| R3 | Main support | `mise use flutter@main` resolves to `main-<sha>`, installs a shallow Git checkout, and later upgrades to a newer snapshot |
| R4 | Specific Git commit | `mise use flutter@git-<sha>` installs that commit; released commits use the official archive and official SHA-256 |
| R5 | macOS / Linux / Windows | Fixture integration tests pass on all three in CI; nightly real installs pass on all three |
| R6 | Dart version auto-detection | `mise exec -- dart --version` reports the bundled Dart; `mise env` exposes the detected Dart version; no separate `dart` tool is required |
| R7 | Official SHA-256 verification | A tampered archive fails the install; the official index's checksum is used, never a locally invented one |
| R8 | One plugin for all channels | A single `metadata.lua` + hooks tree handles every request kind; no duplicate shell installers |
| R9 | Reproducibility | `mise lock` records per-platform URLs and checksums for archive-backed versions; `mise install --locked` works for them |
| R10 | Real project quality | README, LICENSE, CI, tests, release instructions, and no secrets or machine-specific paths |

Out of scope for `v0.1.0`:

- Building Flutter from source / custom engines.
- `dev` channel (obsolete; reject with a pointer to `main`).
- Linux arm64 and Windows arm64 native SDKs (Flutter does not publish them).
- FVM cache directories and `.fvm/fvm_config.json` (`.fvmrc` is a P2 stretch).
- Registry submission to `mise-versions` (mise policy excludes new
  asdf/vfox-backed tools; distribution is the repository URL).
- Automatic installation of Android SDK, Xcode, Visual Studio, or engine
  artifacts (`flutter precache` remains the user's choice).

---

## 2. Why a Lua tool plugin

### 2.1 Options evaluated

| Option | Channels / commits | SHA-256 verified by mise | Lockfile URL + checksum | Windows | Verdict |
| --- | --- | --- | --- | --- | --- |
| Built-in `http:flutter` | Stable list only | Backend-dependent; no channel/commit logic | Backend-dependent | Yes | Not enough |
| asdf plugin (shell) | Stable/beta only | No (plugin downloads itself) | No | No | Rejected |
| Lua **backend** plugin | Could resolve aliases and concrete versions | No, `BackendInstall` downloads itself | No | Yes | Rejected |
| Core tool in mise (Rust) | Possible | Yes | Yes | Yes | Out of scope; not a standalone GitHub project |
| Lua **tool** plugin | Any version string, including commits | Yes, `PreInstall` checksum | Yes, URLs from hooks | Yes | **Chosen** |

A backend plugin's alias support is attractive, but the mise documentation is
explicit: mise does not verify what `BackendInstall` downloads and records no
download URL or checksum for backend-plugin tools. That directly conflicts with
R7 and R9. A tool plugin gives mise the download, verification, extraction,
lockfile and upgrade logic.

### 2.2 Constraints discovered (and how the design handles them)

1. **`PreInstall` cannot rename the install directory.** Returning a concrete
   version does not change `installs/flutter/<requested>`. Channels therefore
   use either a channel directory (`stable`) or a snapshot-shaped version
   (`main-<sha>`).
2. **Lua has no hash function.** Official SHA-256 must come from the release
   index; Git installs rely on the commit hash.
3. **`Available` receives no tool options.** Version listing must not depend on
   `bootstrap` or other options.
4. **Locked mode requires URLs for tool plugins.** Archive-backed requests
   satisfy this. Git checkouts do not; the limitation is documented.
5. **Rolling channels need a checksum to detect updates.** `stable`/`beta`
   return the current platform archive's official SHA-256 as the rolling
   checksum. `main` snapshots are immutable versions and need none.

### 2.3 One plugin, two artifact providers

```text
request ──► classify
              ├─ stable / beta ─────────────► official archive provider
              ├─ exact release ─────────────► official archive provider
              ├─ git-<sha> (released) ──────► official archive provider
              ├─ git-<sha> (unreleased) ────► git provider
              └─ main / main-<sha> ─────────► git provider
```

Both providers share the same request parser, platform resolver, install
verifier, marker writer, environment hook and tests. There is no separate
installer script for channels.

---

## 3. Version model

### 3.1 Request grammar

| Request | Kind | Install directory | Provider |
| --- | --- | --- | --- |
| `latest` | mise-resolved | newest stable release, e.g. `3.47.9` | official archive |
| `stable` | rolling channel | `stable` | official archive (current stable) |
| `beta` | rolling channel | `beta` | official archive (current beta) |
| `main` | moving branch | `main-<12 hex>` when listing works; `main` as fallback | git |
| `main-<12 hex>` | immutable snapshot | `main-<12 hex>` | git (or official archive if the commit is a release) |
| `git-<7..40 hex>` | commit | `git-<normalized hex>` | official archive if released, else git |
| `<release version>` | exact release | the version string, unchanged | official archive |
| `dev` | rejected | — | error |

Notes:

- Version strings are **opaque**. Do not strip a `v` prefix, do not rewrite
  `3.50.0-0.4.pre`, and do not sort with a SemVer parser. Old releases are
  published as `v1.9.1+hotfix.6`; that is the string users must request.
- `latest` is handled by mise's normal resolution. `Available` must list
  channels and `main-<sha>` entries in a way that does not become mise's
  "latest" (verified: mise picks the newest numeric stable version and skips
  prereleases).
- Prereleases are hidden by `mise ls-remote` and prefix resolution. To install a
  beta build directly, request the exact string (`3.50.0-0.4.pre`) or use
  `beta`.
- Lowercase hex only. Normalize `git-ABC123` to `git-abc123`.
- Accept 7 to 40 hex characters for `git-`. Fewer than 7 is rejected.

### 3.2 Examples

```toml
[tools]
flutter = "stable"                     # follows stable, upgrades in place
# flutter = "beta"                     # follows beta
# flutter = "3.47.9"                   # exact pin
# flutter = "3.50.0-0.4.pre"           # exact beta
# flutter = "main"                     # latest main snapshot
# flutter = "main-fffd8c22ae64"        # pin a main snapshot
# flutter = "git-c197ca5199e9ee5661e865596c9c07294dfab51c"
```

```toml
# Pre-download the bundled Dart SDK at install time (optional).
[tools]
flutter = { version = "stable", bootstrap = true }
```

CLI equivalents:

```sh
mise use flutter@stable
mise use flutter@beta
mise use flutter@3.47.9
mise use flutter@main
mise use flutter@git-c197ca5199e9ee5661e865596c9c07294dfab51c
mise upgrade flutter          # stable/beta rolling checksum, main snapshot
mise install --force flutter@stable
```

### 3.3 Why `main` is a snapshot

`main` is a moving branch with no official archive and no checksum. Listing
`main-<12 hex>` entries (from the GitHub API) gives:

- a deterministic install directory;
- normal `mise outdated` / `mise upgrade` behavior (verified: the old snapshot
  is pruned after 24 hours);
- no fake checksum;
- a version string that identifies the exact commit.

If the GitHub API is unavailable, `Available` omits the snapshot. An explicit
`mise install flutter@main` then falls back to a `main` directory cloned from
the current `master` HEAD. That fallback is deliberately not the primary path;
document it as "offline/rate-limited fallback" and note that upgrades require
`mise install --force flutter@main`.

### 3.4 Channel semantics

- `stable`: `current_release.stable` hash → release entry for this platform.
- `beta`: `current_release.beta` hash → release entry for this platform.
- The channel entry in `Available` has `rolling = true` and `checksum` equal to
  the current platform archive's official SHA-256. `PreInstall` returns the same
  URL and checksum.
- A channel install is a single directory (`installs/flutter/stable`). Switching
  to an exact version creates a separate directory; both can coexist.
- `mise upgrade flutter` reinstalls a channel when the checksum changes.
- `mise lock` records the channel's per-platform URL and checksum. The version
  in the lockfile stays `stable`; the checksum pins the bytes.

---

## 4. Sources of truth

### 4.1 Official release index

Base URL (override with `FLUTTER_STORAGE_BASE_URL`, same variable Flutter uses):

```text
https://storage.googleapis.com
```

Index URL:

```text
<base>/flutter_infra_release/releases/releases_<index-os>.json
```

`<index-os>` is `macos`, `linux` or `windows`.

Archive URL:

```text
<base>/flutter_infra_release/releases/<entry.archive>
```

Do not trust `entry.archive` as a URL: validate it is a relative path with no
scheme, no leading `/`, no `..` segment, and no backslash.

Index fields used:

| Field | Use |
| --- | --- |
| `base_url` | Not used for URL construction; kept for diagnostics only |
| `current_release.{stable,beta}` | Channel resolution |
| `releases[].hash` | Commit matching, channel resolution |
| `releases[].channel` | `stable` / `beta` / `dev` filtering |
| `releases[].version` | Exact version matching and display |
| `releases[].dart_sdk_version` | Expected Dart version when the SDK is not bootstrapped |
| `releases[].dart_sdk_arch` | Architecture preference when present |
| `releases[].release_date` | `created_at` for `minimum_release_age` |
| `releases[].archive` | Relative archive path |
| `releases[].sha256` | Official checksum (required) |

Rules:

- Ignore `dev` entries.
- Ignore entries without a valid 64-hex `sha256`? No: fail closed only when the
  selected entry lacks one. Never select an entry and then drop the checksum.
- `dart_sdk_arch` is missing on many older entries; infer arm64 from an
  `_arm64_` or `arm64` segment in `archive`, otherwise x64.
- A version may appear twice on macOS (x64 and arm64). Deduplicate after
  choosing the host/target architecture.
- Preserve index order for `Available`; it is newest first.

### 4.2 GitHub API

Used only for:

- current `master` HEAD (`main-<sha>` snapshots);
- resolving a short commit SHA to a full SHA.

Endpoints:

```text
https://api.github.com/repos/flutter/flutter/commits/master
https://api.github.com/repos/flutter/flutter/commits/<short-sha>
```

Headers:

```lua
{ ["Accept"] = "application/vnd.github+json" }
```

mise automatically adds the resolved GitHub token to `api.github.com` requests
and sets an API version header; do not implement token handling. Document
`MISE_GITHUB_TOKEN` / `GITHUB_TOKEN` for rate limits.

Failure policy:

- In `Available`: a failed HEAD lookup is a warning; omit the `main-<sha>`
  entry and still return stable/beta/versions.
- In `PreInstall` for an explicit `main-<sha>` or short `git-<sha>`: failure is
  an error, because the request cannot be resolved deterministically. Include
  the HTTP status and a hint about the token/rate limit.
- Never print the token or the `Authorization` header.

### 4.3 Git repository

```text
https://github.com/flutter/flutter.git
```

Only `flutter/flutter` is supported. Do not accept an arbitrary repository URL.

### 4.4 Trust model

| Artifact | Integrity source | Strength |
| --- | --- | --- |
| Official archive (stable/beta/exact/released commit) | `sha256` in the official release index, verified by mise | Strong against corruption; trust anchored in the index host |
| Git checkout (`main`, arbitrary commit) | Full commit SHA checked out; `git rev-parse HEAD` must match | Strong content addressing; trust anchored in GitHub |
| Mirror (`FLUTTER_STORAGE_BASE_URL`) | Checksums from the mirror's index | Same as above, but the mirror operator is trusted; document this |

The plugin must not claim a Git checkout has an "official SHA-256". The docs
must say: archives are SHA-256 verified; Git installs are commit-verified.

---

## 5. Platform and artifact selection

### 5.1 Platform mapping

| `RUNTIME.osType` | Index | `RUNTIME.archType` | Support |
| --- | --- | --- | --- |
| `darwin` | `macos` | `arm64` | arm64 archive preferred; x64 fallback (Rosetta) |
| `darwin` | `macos` | `amd64` | x64 only; arm64-only release is an error |
| `linux` | `linux` | `amd64` | x64 only |
| `linux` | `linux` | `arm64` | error: Flutter does not publish Linux arm64 SDKs |
| `windows` | `windows` | `amd64` | x64 |
| `windows` | `windows` | `arm64` | x64 under emulation, with a warning (best effort) |
| anything else | — | — | error |

Error text must include the detected OS/arch and a supported combination.

### 5.2 Selection algorithm

```text
function select_entry(entries, os, arch):
    candidates = entries filtered to channel in {stable, beta}

    if arch == "arm64" and os == "macos":
        arm = candidates where entry_arch(e) == "arm64"
        if arm not empty: return first(arm)
        x64 = candidates where entry_arch(e) == "x64"
        if x64 not empty:
            log.warn("no arm64 Flutter SDK for this version; using x64 under Rosetta")
            return first(x64)
        error("no macOS archive for this version")

    if arch == "arm64" and os == "linux":
        error("Flutter does not publish Linux arm64 SDKs; use an x64 machine")

    if arch == "arm64" and os == "windows":
        x64 = candidates where entry_arch(e) == "x64"
        if x64 not empty:
            log.warn("using the x64 Flutter SDK under Windows emulation")
            return first(x64)
        error("no Windows archive for this version")

    if arch == "amd64":
        x64 = candidates where entry_arch(e) == "x64"
        if x64 not empty: return first(x64)
        error("this release has no x64 archive")
```

`entry_arch(e)`:

```lua
if e.dart_sdk_arch == "arm64" then return "arm64" end
if e.dart_sdk_arch == "x64" then return "x64" end
if e.archive:find("arm64", 1, true) then return "arm64" end
return "x64"
```

### 5.3 Exact version lookup

1. Filter `releases` to `entry.version == request`.
2. Keep `stable` and `beta`; prefer `stable` if both exist.
3. Apply the architecture selection above.
4. If no entry: error with the request, OS/arch, and the suggestion
   `mise ls-remote flutter`.

Do not normalize the version (no `v` stripping, no whitespace trimming beyond
the request itself).

### 5.4 Channel lookup

1. `hash = index.current_release[channel]`.
2. If missing: error `release index has no current <channel> release`.
3. Candidates = entries with `hash == hash` and `channel == channel`.
4. Apply architecture selection.
5. Validate the entry has `version`, `archive`, `sha256`.

### 5.5 Duplicate and ordering rules

- `Available` returns newest first, as required by mise.
- Use the index order (already newest first); do not sort with `semver`.
- Deduplicate by version after selecting the architecture, preserving the first
  occurrence.
- Put channel entries first, then the `main-<sha>` snapshot, then releases. This
  is safe: mise's `latest` ignores non-numeric entries (verified).
- `mise ls-remote` reverses the list for display, so channels appear last.

---

## 6. Hook contract

### 6.1 `metadata.lua`

```lua
PLUGIN = {
    name = "flutter",
    version = "0.1.0",
    description = "Install the Flutter SDK with mise (stable, beta, main, commits)",
    homepage = "https://github.com/Minessential/mise-flutter",
    license = "MIT",
    legacyFilenames = { ".flutter-version" },
}
```

- `name` must be `flutter`; users install the plugin under that name.
- Do not put logic in `metadata.lua`.
- `legacyFilenames` is implemented; see §6.7.

### 6.2 `Available`

File: `hooks/available.lua`
Ctx: `{ args = {} }` (unused).

Behavior:

1. Load the release index for the **target** platform (`RUNTIME`, not `uname`).
2. Build `stable` and `beta` entries:
   ```lua
   { version = "stable", rolling = true, checksum = <host archive sha256> }
   ```
   Omit a channel if its current release has no archive for this platform.
3. Try the GitHub API for `master`; on success add:
   ```lua
   { version = "main-fffd8c22ae64", created_at = "2026-11-10T06:20:38Z" }
   ```
   The SHA is the first 12 lowercase hex characters of the full SHA. Do not add
   a literal `main` entry (it would shadow prefix resolution).
4. Add every stable/beta release version once, with `created_at =
   release_date`, newest first, using the architecture selection.
5. Return the list.

Failure policy:

- Index HTTP/parse failure: `error()` with the URL and status. Do not return an
  empty list.
- GitHub failure: `log.warn` (debug-level details) and continue.
- A channel whose archive is missing on this platform: omit the channel but
  keep versions; `PreInstall` still produces a clear error if requested.

Do not read tool options here.

### 6.3 `PreInstall`

File: `hooks/pre_install.lua`
Ctx: `{ version, options }`.
Returns: `{ version = ctx.version, url = ..., sha256 = ... }` or
`{ version = ctx.version }` for a Git install.

Classifier:

```text
v = ctx.version
if v == "dev": error("the dev channel is obsolete; use main or beta")
if v == "stable" or v == "beta": channel flow
if v matches ^main%-([0-9a-f]{12})$: main snapshot flow
if v == "main": main fallback flow (resolve HEAD, cache SHA, no URL unless released)
if v matches ^git%-([0-9a-f]{7,40})$: commit flow
else: exact release flow
```

Channel flow:

```lua
local index = load_index()
local entry = channel_entry(index, v)       -- §5.4
local url = archive_url(entry)
return { version = v, url = url, sha256 = entry.sha256 }
```

Exact flow:

```lua
local entry = exact_entry(index, v)         -- §5.3
return { version = v, url = archive_url(entry), sha256 = entry.sha256 }
```

Commit flow:

1. Normalize hex to lowercase.
2. Resolve to a full SHA:
   - 40 chars: use as-is.
   - 7–39: call GitHub `commits/<short>`; error with status/hint on failure.
3. Look for a release entry with `hash == full_sha` for this platform:
   - If found: return the official archive URL + `sha256` (the install is
     byte-for-byte the published release, even though the directory is named
     `git-<sha>`).
   - If not found: write the full SHA to the commit cache and return
     `{ version = ctx.version }` (no URL, no checksum).
4. Never run Git in `PreInstall`; `mise lock` may call this hook for other
   platforms, and it must not install anything.

Main snapshot flow:

1. `main-<12>`: resolve the full SHA via `commits/<12>` (cache it). If the SHA
   matches a published release, use the archive path; otherwise return no URL.
2. `main`: resolve `commits/master` to a full SHA, cache it, and use the
   archive path if the SHA matches a release (normally not). Otherwise return no
   URL.

Errors:

- Missing `sha256`: `error("release index has no sha256 for <archive>")`.
- Invalid/absolute/escaping archive: error.
- Index HTTP failure: error.

`PreInstall` must be free of host probing (`uname`, `os.getenv("HOME")`, file
existence outside the plugin cache). It may read `FLUTTER_STORAGE_BASE_URL` and
tool options, which are configuration, not host probes.

### 6.4 `PostInstall`

File: `hooks/post_install.lua`
Ctx: `{ rootPath, runtimeVersion, sdkInfo, options }`.

This hook must be idempotent: `MiseInstallSatisfied` can trigger it again on an
existing install without a download.

Steps:

1. Read `request = ctx.runtimeVersion`.
2. Determine `source`:
   - archive if the request is a channel, exact release, or a commit that the
     index resolves to a release;
   - git otherwise.
3. Archive path:
   - Verify `bin/flutter` (Unix) or `bin/flutter.bat` (Windows) exists. On
     Windows, mention antivirus quarantine if missing.
   - Load the index once to obtain `version`, `channel`, `hash`,
     `dart_sdk_version`, `archive`, `sha256` for the marker. If the index is
     unavailable at this point, write the marker with `dart_sdk_version = nil`
     and a warning; do not fail a successfully extracted SDK.
4. Git path:
   - Require `git`; check `git --version` and produce an actionable error
     (install Git, or use stable/beta instead).
   - Resolve the full SHA from the commit cache (written by `PreInstall`) or
     call the GitHub API again.
   - `git init` in `ctx.rootPath`.
   - Set the remote to `https://github.com/flutter/flutter.git` (set-url, then
     add if that fails).
   - `git fetch --depth 1 origin <full-sha>` with a generous timeout (1800 s).
   - `git checkout -B master FETCH_HEAD` for `main`/`main-*`; `git checkout
     --detach FETCH_HEAD` for `git-*`.
   - `git rev-parse HEAD` must equal the full SHA; otherwise error.
   - Verify the Flutter executables exist.
5. Optional bootstrap (see §7):
   - if `ctx.options.bootstrap == "true"` (string comparison!) run the
     bootstrap command;
   - on success, read `bin/cache/flutter.version.json` and use its
     `dartSdkVersion` / `frameworkRevision`;
   - on failure, error with the command, the captured stderr, and the hint to
     retry with `bootstrap = false`.
6. Write `<root>/.mise-flutter.json` (see §6.5) with `io.open`.
7. Log one concise line: request, resolved version, channel/source, Dart
   version if known.

Do not write outside `ctx.rootPath` except the plugin cache directory
(`RUNTIME.cacheDirPath`) used for commit SHA resolution.

### 6.5 Marker file

Path: `<root>/.mise-flutter.json`
Written by: `PostInstall`
Read by: `EnvKeys`, `MiseInstallSatisfied`, tests.

```json
{
  "schema": 1,
  "request": "stable",
  "version": "3.47.9",
  "channel": "stable",
  "source": "archive",
  "framework_revision": "c197ca5199e9ee5661e865596c9c07294dfab51c",
  "dart_sdk_version": "3.13.7",
  "archive": "stable/macos/flutter_macos_arm64_3.47.9-stable.zip",
  "sha256": "6545b8...",
  "bootstrapped": false
}
```

- `request`: the version string mise passed to `PostInstall`.
- `version`: the resolved Flutter version when known; for a git checkout with an
  unknown framework version, use `"0.0.0-unknown"`.
- `channel`: `stable`, `beta`, `main`, or `"unknown"` for an arbitrary commit.
- `source`: `"archive"` or `"git"`.
- `framework_revision`: release hash or full Git SHA.
- `dart_sdk_version`: expected (index) or actual (bootstrap); `null` if unknown.
- `bootstrapped`: whether `bin/cache/dart-sdk` was created by the plugin.
- Write valid JSON with `json.encode`; use `io.open(path, "w")`. If writing
  fails, error rather than silently leaving an unidentifiable install.

### 6.6 `EnvKeys`

File: `hooks/env_keys.lua`
Ctx: `{ path, version, main, sdkInfo, options }`.
Returns: a list of `{ key, value }`.

Required:

```lua
{ key = "FLUTTER_ROOT", value = ctx.path }
{ key = "PATH", value = file.join_path(ctx.path, "bin") }
```

Optional, in order:

1. `MISE_FLUTTER_REVISION` from the marker's `framework_revision`, or from
   `bin/cache/flutter.version.json`.
2. `MISE_FLUTTER_CHANNEL` from the marker's `channel`, or the version file.
3. `MISE_FLUTTER_DART_VERSION`:
   - actual: contents of `bin/cache/dart-sdk/version`, trimmed;
   - else expected: marker `dart_sdk_version`;
   - omit if neither.
4. `DART_SDK` = `<root>/bin/cache/dart-sdk` only if that directory exists.

Caching:

- Use `pcall(require, "mise.cache")` and `watch_files` for:
  - `<root>/.mise-flutter.json`
  - `<root>/bin/cache/dart-sdk/version`
  - `<root>/bin/cache/flutter.version.json`
- Do not call the network.
- Do not set `PUB_CACHE`, `FLUTTER_STORAGE_BASE_URL`, or `PATH` entries for
  Android/Xcode. Only the SDK's own `bin`.

Do not return `DART_SDK` pointing at a missing directory: IDE integrations treat
an invalid path as an error.

### 6.7 `ParseLegacyFile`

File: `hooks/parse_legacy_file.lua`
Ctx: `{ filename, filepath, getInstalledVersions }`.

v1 behavior:

- `.flutter-version`: read the first non-empty line, trim trailing whitespace,
  return `{ version = line }`.
- Return `nil` for unknown content.

P2 (only if the schedule allows): `.fvmrc`, parse JSON and return the `flutter`
field. Add `.fvmrc` to `legacyFilenames` only when implemented.

README must tell users to enable:

```toml
[settings]
idiomatic_version_file_enable_tools = ["flutter"]
```

### 6.8 `MiseInstallSatisfied`

File: `hooks/mise_install_satisfied.lua`
Ctx: `{ path, version, options }`.
Return: `{ satisfied = false, reason = "..." }` or `{ satisfied = true }`.

Checks (local only, no network, no Git commands):

- `bin/flutter` (Unix) or `bin/flutter.bat` (Windows) exists.
- If `bootstrap == "true"` and `bin/cache/dart-sdk/version` is missing, return
  false with reason `"Dart SDK has not been bootstrapped"`. This makes enabling
  the option repair an existing install without re-downloading.
- If the request is a commit/main snapshot and the marker is missing, return
  false with reason `"missing .mise-flutter.json"`.
- Otherwise true.

A false result reruns `PostInstall` without `PreInstall`, a download, or
deleting the install directory. That is why `PostInstall` must be idempotent.

### 6.9 Error catalog

Use these messages (substitute values):

```text
flutter: unsupported platform <os>/<arch>
flutter: Flutter does not publish Linux arm64 SDKs; use an x64 machine
flutter: version <v> not found for <os>/<arch>; run `mise ls-remote flutter`
flutter: release index <url> returned HTTP <status>
flutter: release index has no current <channel> release
flutter: release index has no sha256 for <archive>
flutter: commit <sha> was not found in flutter/flutter
flutter: GitHub API returned HTTP <status>; set MISE_GITHUB_TOKEN to raise the rate limit
flutter: git is required for main and commit installs; install Git and retry
flutter: git fetch failed for <sha>; the commit must be reachable in flutter/flutter
flutter: checkout is at <actual>, expected <sha>
flutter: the archive did not contain bin/flutter (on Windows, check antivirus quarantine)
flutter: Dart SDK bootstrap failed: <stderr>; retry with bootstrap = false to install without it
```

Errors must be short (one line for the cause), actionable, and must not contain
tokens or full response bodies.

---

## 7. Dart SDK auto-detection

### 7.1 Model

Flutter ships a Dart SDK wrapper at `<root>/bin/dart` (`dart.bat` on Windows).
The wrapper downloads the matching Dart SDK into `<root>/bin/cache/dart-sdk` on
first use and executes it. Therefore:

- Put `<root>/bin` on `PATH`; do not install a second Dart SDK.
- Do not use mise's `dart` backend for the bundled Dart.
- `dart --version` always matches the selected Flutter SDK.

### 7.2 Version detection precedence

1. `<root>/bin/cache/dart-sdk/version` (actual, authoritative).
2. `bin/cache/flutter.version.json` → `dartSdkVersion` (actual, from Flutter).
3. Marker `dart_sdk_version` (expected, from the official release index).
4. Unknown.

`EnvKeys` returns `MISE_FLUTTER_DART_VERSION` from (1), else (2), else (3).

For archive installs, the expected version comes from the release index, so the
variable is available immediately even before the SDK is downloaded. For Git
installs, it becomes available after the first Flutter invocation (or after
`bootstrap = true`).

### 7.3 Optional bootstrap

Tool option: `bootstrap = true` (TOML boolean; arrives in Lua as the string
`"true"`). Default: `false` (lazy, matching Flutter's own behavior).

When true, `PostInstall` runs, from `ctx.rootPath`:

```sh
# Unix
./bin/flutter --suppress-analytics --version --machine

# Windows
.\bin\flutter.bat --suppress-analytics --version --machine
```

with a 1800-second timeout. On success:

- read and parse `bin/cache/flutter.version.json`;
- set marker `bootstrapped = true` and `dart_sdk_version` to the actual value;
- log the Dart version.

On failure:

- error with the captured stderr, the command, and the `bootstrap = false`
  hint;
- do not leave a marker claiming success.

The plugin must not run `flutter precache`, `flutter doctor`, or any command that
downloads Android/iOS/web engine artifacts. Those are large and
platform-specific; document `flutter precache` as a user step.

### 7.4 Why not install `dart` as a dependency

A second Dart SDK can drift from Flutter's bundled Dart, and mise's tool-name
routing can shadow the bundled `dart` (verified: `mise exec -- dart` consults a
configured `dart` tool). The plugin README must warn:

> Do not configure a separate `dart` tool when using this plugin. Flutter's
> `bin` provides the matching Dart. If `mise exec -- dart` complains about a
> shim, remove the `dart` entry from your mise config.

### 7.5 Disk and network notes

- The stable archive is roughly 1.6–2.3 GB compressed (2026-11 data).
- The first Flutter invocation downloads/builds roughly 600 MB in
  `bin/cache`.
- `bootstrap = false` keeps `mise install` limited to the archive download.
- The README must document both sizes and how to clear downloads
  (`mise cache clear`).

---

## 8. Security requirements

1. **Fail closed on checksums.** Every `url` returned for an official archive
   must carry the index's `sha256`. Never return `sha256 = nil` for an archive.
2. **Validate archive paths.** Reject `://`, leading `/`, `..` segments,
   backslashes, and empty paths. Construct URLs with `string` concatenation
   only after validation.
3. **Validate commit hex.** Accept only `[0-9a-f]{7,40}` after lowercasing.
   Never interpolate an unvalidated version into a shell command.
4. **Use `cmd.exec` with `cwd`.** Do not build `cd <path> && ...` strings. Pass
   `cwd = ctx.rootPath`; the path may contain spaces or parentheses.
5. **No `os.execute`.** Capture errors with `cmd.exec` and `pcall`; do not rely
   on the shell's exit status silently.
6. **No secrets in logs.** Do not log headers, tokens, or response bodies from
   authenticated requests.
7. **No writes outside the install directory** except `RUNTIME.cacheDirPath`
   (commit SHA cache). Do not edit user configuration, npm/pip settings, or
   Flutter's global config.
8. **Mirror caveat.** When `FLUTTER_STORAGE_BASE_URL` is set, checksums come
   from that host. The README must say so; the default is the official host.
9. **Symlink escape.** Official archives are extracted by mise, which rejects
   symlinks leading out of the install directory. Do not add custom extraction.
10. **No remote code from the release index.** Only use `sha256`, `archive`,
    versions and metadata; never execute a field.

Threat table:

| Threat | Mitigation |
| --- | --- |
| Corrupted download | Official SHA-256 verified by mise |
| Compromised mirror | Visible caveat; users can unset the mirror; checksums still detect corruption |
| Wrong commit fetched | `git rev-parse HEAD` equality check |
| Shell injection via version | Strict regex for commits/channels; exact versions only used after index match |
| Path traversal via archive | Relative-path validation plus mise's extractor |
| Token leakage | No header logging; rely on mise's HTTP client |
| Partial install treated as complete | `PostInstall` verifies executables and writes a marker; `MiseInstallSatisfied` rechecks |

---

## 9. Repository layout and code standards

```text
mise-flutter/
├── metadata.lua
├── hooks/
│   ├── available.lua
│   ├── pre_install.lua
│   ├── post_install.lua
│   ├── env_keys.lua
│   ├── mise_install_satisfied.lua
│   └── parse_legacy_file.lua
├── lib/
│   ├── flutter.lua       -- constants, URLs, platform mapping, errors
│   ├── releases.lua      -- index loading, selection, validation
│   ├── requests.lua      -- request classification
│   ├── git.lua           -- git checks/commands/commit cache
│   └── install.lua       -- marker, verify, bootstrap, Dart detection
├── tests/
│   ├── integration.sh
│   ├── fixtures/
│   │   ├── storage/...   -- local release indexes and tiny archives
│   │   └── archive/...   -- committed fixtures
│   └── lib/              -- optional helpers
├── mise-tasks/
│   ├── test
│   ├── lint
│   └── test-fixture
├── mise.toml
├── .github/workflows/ci.yml
├── docs/
│   ├── DESIGN.md
│   └── RESEARCH.md
├── README.md
├── LICENSE
├── .gitignore
├── .luarc.json
└── stylua.toml
```

Rules:

- Lua 5.1 syntax only. No `goto`, no integer division, no `//`, no `utf8`
  library, no `table.unpack` (use `unpack` if needed).
- Load shared code with `require("flutter")`, `require("releases")`, etc.;
  `require` searches the plugin root, `hooks/` and `lib/`.
- Hooks are thin: classify, call a library, return. Business logic lives in
  `lib/` so it is readable and testable.
- No module-level side effects (no HTTP, no file writes, no `os.getenv` at load
  time). `metadata.lua` is assignments only.
- Prefer `log.info` / `log.warn` / `log.debug` over `print`; `print` is
  `log.info` and writes to stderr.
- Quote/validate every interpolated value. Pass paths via `cwd` and `env`, not
  string concatenation.
- Format with `stylua` (2-space indent, 100-column width, `Unix` line endings).
- Keep functions under ~60 lines; split selection, validation and I/O.
- Comments explain *why* (a policy, a Flutter quirk), not *what*.

Module API (minimum):

```lua
-- lib/flutter.lua
M.REPO_URL
M.DEFAULT_STORAGE_BASE
M.index_os()                 -- "macos" | "linux" | "windows"
M.storage_base()             -- env override or default, trailing slash removed
M.index_url()                -- full releases_<os>.json URL
M.archive_url(archive_path)  -- validated relative path -> full URL
M.is_windows()
M.supported_platform()       -- returns os, arch or raises

-- lib/releases.lua
M.load()                     -- decoded index table
M.channel_entry(index, channel)
M.exact_entry(index, version)
M.find_hash(index, sha)
M.select_arch(entries, os, arch)
M.entry_arch(entry)
M.validate_entry(entry)
M.version_from_hash(index, sha, channel)

-- lib/requests.lua
M.classify(version)          -- { kind, channel, sha, short, raw }
M.is_main_snapshot(version)
M.is_commit(version)

-- lib/git.lua
M.ensure_available()
M.resolve_full_sha(short)
M.cache_sha(short, full)
M.cached_sha(short)
M.checkout(root, full_sha, { branch = "master" | nil })
M.head(root)

-- lib/install.lua
M.marker_path(root)
M.read_marker(root)
M.write_marker(root, table)
M.verify_tree(root, os)
M.bootstrap(root, os, timeout)
M.detect_dart_version(root)
M.expected_dart_version(index, request)
```

---

## 10. Testing strategy

### 10.1 Layers

| Layer | What it proves | Cost | Runs |
| --- | --- | --- | --- |
| L1: resolution with a local fixture server | `Available`, channel/arch/commit selection, URL construction, checksum enforcement, `EnvKeys`, marker | seconds, no big downloads | every PR, all 3 OS |
| L2: real index resolution | official URLs, current stable/beta, cross-platform lockfiles, no download | seconds | every PR (Linux + macOS) |
| L3: real install | actual 1.6–2.3 GB download, extraction, bootstrap, `flutter --version`, `dart --version` | 5–15 min per OS | nightly / manual |
| L4: upgrade | `stable` rolling checksum and `main-<sha>` snapshot upgrade | heavy | nightly/manual, optional |

### 10.2 Isolated environment

Every test must set its own directories (from the publishing guide):

```sh
test_dir="$(mktemp -d)"
export MISE_CONFIG_DIR="$test_dir/config"
export MISE_SYSTEM_CONFIG_DIR="$test_dir/system"
export MISE_GLOBAL_CONFIG_FILE="$test_dir/global.toml"
export MISE_DATA_DIR="$test_dir/data"
export MISE_CACHE_DIR="$test_dir/cache"
export MISE_STATE_DIR="$test_dir/state"
export MISE_ENV_CACHE=0
export MISE_YES=1
```

Also unset `MISE_*` variables that could change behavior (`MISE_SAFE`,
`MISE_DISABLE_BACKENDS`, `MISE_OFFLINE`, ...) and set
`FLUTTER_STORAGE_BASE_URL` to the fixture server for L1.

Never run tests against the user's real mise data. Never leave processes or temp
directories behind.

### 10.3 L1: fixture server

Create `tests/fixtures/storage/flutter_infra_release/releases/` with three JSON
indexes. Each index has:

- `current_release.stable` and `.beta` hashes pointing at fixture entries;
- one stable entry (`9.9.9`), one beta entry (`9.9.10-0.1.pre`);
- `archive` paths for `stable/<os>/...` and `beta/<os>/...`;
- valid 64-hex `sha256` values matching the committed tiny archives;
- one macOS arm64 duplicate for the stable version, with a different archive
  and checksum;
- `dart_sdk_version` values (e.g. `7.7.7`).

Tiny archives are committed (each under ~50 KB) or generated by a deterministic
script checked into `tests/`. They contain:

```text
flutter/bin/flutter       (exit 0, prints "Flutter fixture 9.9.9")
flutter/bin/dart          (prints a fake Dart version)
flutter/bin/flutter.bat   (Windows equivalent)
flutter/bin/dart.bat
```

Use `.tar.xz` for the Linux fixture if `xz` is available in CI; otherwise use
`.zip` for all platforms. The fixture index's `archive` suffix drives mise's
extractor, so the test can cover `.tar.xz` on Linux and `.zip` elsewhere.

Server: `python3 -m http.server <port> --directory tests/fixtures/storage` (or a
20-line Python script that records requests and serves with the right
`Content-Length`). Start it in the background, wait for the port, and kill it in
a `trap`.

Assertions:

1. `mise plugins link flutter "$REPO"`.
2. `mise ls-remote flutter` contains `9.9.9`, `beta`, `stable`.
3. `mise install` with:

   ```toml
   [tools]
   flutter = { version = "stable", bootstrap = false }
   ```

   succeeds; `installs/flutter/stable/bin/flutter` exists; the marker has
   `source = "archive"`, `sha256` matching the fixture, and `bootstrapped =
   false`.
4. `mise exec -- flutter --version` prints the fixture string (the shim path is
   exercised).
5. `mise env` contains `FLUTTER_ROOT`, `PATH` with `<root>/bin`,
   `MISE_FLUTTER_DART_VERSION = 7.7.7`, and no `DART_SDK` before bootstrap.
6. `mise install flutter@9.9.10-0.1.pre` installs the beta fixture.
7. `mise install flutter@git-<released fixture sha>` uses the archive (assert the
   marker source/sha), not Git.
8. `mise lock --platform macos-arm64,linux-x64,windows-x64` writes URLs and
   checksums for all three; assert per-platform archive names and checksums.
9. Tamper test: a second fixture index with a wrong `sha256`; install must fail
   with a checksum error and must not leave a usable `bin/flutter`.
10. Missing `bin/flutter` fixture: install fails with the antivirus hint on
    Windows and the generic hint elsewhere.
11. Unsupported platform: a fixture index with no Linux arm64 entry; `mise lock
    --platform linux-arm64` fails with the arm64 message (run on any host via
    `mise lock`).
12. Path with spaces: set `MISE_DATA_DIR="$test_dir/data dir"` in a second run;
    install and exec succeed.

### 10.4 L2: real index, no download

On Linux and macOS CI:

```sh
# Isolated env, project with [tools] flutter = { version = "3.47.9", bootstrap = false }
mise plugins link flutter "$REPO"
mise ls-remote flutter | grep -qx '3.47.9'
mise ls-remote flutter | grep -qx 'stable'
mise lock --platform macos-arm64,macos-x64,linux-x64,windows-x64
test -s mise.lock
grep -q 'sha256:' mise.lock
grep -q 'https://storage.googleapis.com/flutter_infra_release/releases/' mise.lock
```

`mise lock` calls `PreInstall` for each platform without downloading. This is
the cheapest way to test cross-platform URL and checksum selection.

Also assert:

- `mise latest flutter` is a stable numeric version, not `stable`/`beta`/`main-*`;
- `mise install flutter@3.47.9 --dry-run` succeeds;
- `mise install flutter@git-c197ca5199e9ee5661e865596c9c07294dfab51c` resolves to
  the archive for the current platform (use `mise lock` on a temp project to
  avoid the download).

### 10.5 L3: real install (nightly)

Matrix: `ubuntu-latest`, `macos-14` (arm64), `windows-latest`. Optionally
`macos-13`/an Intel runner for x64.

```sh
mise plugins link flutter "$REPO"
mise use flutter@3.47.9          # or stable; pin for determinism
mise exec -- flutter --version
mise exec -- flutter --version --machine
mise exec -- dart --version
```

Assertions:

- `flutter --version` contains `3.47.9` (or the pinned version).
- `--machine` JSON has `dartSdkVersion` and `frameworkRevision`.
- `dart --version` reports the same Dart version as the JSON.
- `mise which flutter`/`mise where flutter` point into the isolated data dir.
- On macOS arm64, the installed Dart binary is arm64 (`file
  bin/cache/dart-sdk/bin/dart`); on x64 it is x86_64.
- On Windows, both `flutter` and `dart` resolve through mise shims (`.bat`).
- Run once with `bootstrap = true` in a separate job; assert the marker has
  `bootstrapped = true` and `bin/cache/dart-sdk/version` exists.

Cache `MISE_DATA_DIR` and `MISE_CACHE_DIR` with a key of
`flutter-${{ matrix.os }}-3.47.9` to make the nightly affordable. Do not cache
the plugin checkout.

### 10.6 L4: upgrades (optional nightly)

- `stable`: install, then `mise upgrade flutter` after a new release; at least
  assert `mise outdated` compares checksums without errors.
- `main`: install `main`, then `mise upgrade flutter` and assert a new
  `main-<sha>` directory, with the old one scheduled for pruning. The fixture
  test can cover this deterministically by changing the fixture's `main` SHA.

### 10.7 Windows-specific checks

- `git` present in the runner; `flutter.bat` executed via `cmd.exec` with
  `cwd`.
- A path with spaces (`MISE_DATA_DIR="...\data dir"`).
- Antivirus is not simulated; assert the missing-`flutter.bat` error text.
- `dart.bat` shim works: `mise exec -- dart --version`.
- `FLUTTER_STORAGE_BASE_URL` with `http://127.0.0.1` works (the fixture test).

### 10.8 Manual acceptance checklist

Before release:

```sh
# Stable
mise use flutter@stable
mise exec -- flutter --version
mise exec -- dart --version

# Beta
mise use flutter@beta
mise exec -- flutter --version

# Main
mise use flutter@main
mise ls flutter                 # shows main-<sha>
mise exec -- flutter --version  # 0.0.0-unknown is acceptable

# Commit (released)
mise use flutter@git-c197ca5199e9ee5661e865596c9c07294dfab51c
mise exec -- flutter --version  # prints 3.47.9

# Exact
mise use flutter@3.47.9

# Cleanup
mise uninstall flutter
```

Also verify `mise install --force`, `mise uninstall`, `mise prune`, and a path
with spaces.

---

## 11. CI and release

### 11.1 `mise.toml`

```toml
[env]
MISE_USE_VERSIONS_HOST = "0"   # exercise the plugin, not the generated host

[tools]
stylua = "latest"
actionlint = "latest"

[tasks.lint]
description = "Format check and workflow lint"
run = [
  "stylua --check metadata.lua hooks lib tests",
  "actionlint",
]

[tasks.test]
description = "Fixture integration tests"
run = "bash tests/integration.sh"

[tasks.ci]
depends = ["lint", "test"]
```

Do not add a `lua` tool dependency for tests; the fixture tests run through mise
itself. If a pure unit test harness is added later, use a separate task and keep
it out of the Windows-critical path.

### 11.2 `.github/workflows/ci.yml`

- `lint` job: Ubuntu, `jdx/mise-action@v2`, `mise run lint`.
- `fixture` job: matrix `ubuntu-latest`, `macos-14`, `windows-latest`; checkout,
  `jdx/mise-action@v2`, `bash tests/integration.sh` (Windows uses Git Bash).
- `real-index` job: Ubuntu + macOS; isolated env; `mise lock` cross-platform;
  assert URLs/checksums; no big downloads.
- `real-install` job: `schedule` (nightly) and `workflow_dispatch`; matrix all
  three OS; isolated env; pinned Flutter; run the L3 assertions; cache
  `MISE_DATA_DIR`/`MISE_CACHE_DIR`.
- Permissions: `contents: read` by default. Do not use secrets in PR jobs.
- `GITHUB_TOKEN` for rate limits only if needed; the real-index job can run
  unauthenticated (two API calls).

### 11.3 Release

1. Set `metadata.lua` `version` to the new release.
2. Update README examples if behavior changed.
3. Commit, tag `v0.1.0` (annotated), push the tag.
4. Users pin:
   ```toml
   [plugins]
   flutter = "https://github.com/Minessential/mise-flutter#v0.1.0"
   ```
5. `mise plugins install flutter 'https://github.com/Minessential/mise-flutter#v0.1.0'`.
6. No registry entry. The README must explain that mise does not accept new
   asdf/vfox-backed tools into the registry, and that the repository URL is the
   distribution channel.
7. Note the name collision with `mise-plugins/mise-flutter` (an asdf plugin) in
   the README. The URLs are different; the install name is the same (`flutter`).

### 11.4 Repository metadata

- Description: "Flutter SDK plugin for mise: stable, beta, main and Git commits,
  with official SHA-256 verification and bundled Dart detection."
- Topics: `mise`, `mise-plugin`, `flutter`, `dart`, `version-manager`, `vfox`.
- License: MIT.
- Do not commit `.scratch/`, local mise data, lockfiles from test runs, or
  machine-specific paths.

---

## 12. Implementation plan for pi

Work in this order. Each task ends with a runnable check; do not move on with a
failing check.

### T0 — Scaffold

Files: `metadata.lua`, `hooks/`, `lib/`, `LICENSE`, `.gitignore`, `mise.toml`,
`stylua.toml`, `.luarc.json`.

Acceptance:

- `mise plugins link flutter .` in an isolated env succeeds.
- `mise ls-remote flutter` returns a list (even if only stable/beta at first).
- `mise cache clear flutter` works.

### T1 — Shared library

Files: `lib/flutter.lua`, `lib/releases.lua`, `lib/requests.lua`.

Implement constants, index loading, platform mapping, request classification,
entry validation, arch selection, URL construction. No hooks yet.

Acceptance: a temporary debug hook (removed before commit) prints classified
requests and selected entries for fixture data; no hardcoded host paths.

### T2 — `Available`

Files: `hooks/available.lua`, library helpers.

Acceptance:

- Fixture `mise ls-remote flutter` shows stable, beta, versions and the
  `main-<sha>` entry from a stub API.
- Real `mise ls-remote flutter` shows 3.47.9 and stable.
- No `dev` entries.
- Network failure produces a clear error; GitHub failure does not break stable.

### T3 — Archive `PreInstall`

Files: `hooks/pre_install.lua`.

Acceptance:

- `mise lock --platform macos-arm64,macos-x64,linux-x64,windows-x64` on a
  fixture project writes the expected archive URL and checksum per platform.
- Exact/stable/beta requests resolve.
- Missing checksum is an error.

### T4 — Archive `PostInstall` + marker

Files: `hooks/post_install.lua`, `lib/install.lua`.

Acceptance:

- Fixture `mise install flutter@stable` with `bootstrap = false` installs and
  writes a valid marker.
- Missing `bin/flutter` fixture fails with the right message.
- Rerunning `mise install` does not fail.

### T5 — `EnvKeys`

Files: `hooks/env_keys.lua`.

Acceptance:

- `mise env` shows `FLUTTER_ROOT`, `PATH`, and `MISE_FLUTTER_DART_VERSION` from
  the marker.
- After creating `bin/cache/dart-sdk/version`, `mise env` shows `DART_SDK` and
  the actual version.
- `mise exec -- flutter --version` works for the fixture.

### T6 — Git installs

Files: `lib/git.lua`, `hooks/post_install.lua`, `hooks/pre_install.lua`.

Acceptance (fixture first, then one real shallow fetch on a dev machine):

- `git-<sha>` released commit uses the archive path.
- `git-<unreleased sha>` clones/fetches, checks out, and verifies HEAD.
- Short SHA resolves through the API.
- Missing Git produces the actionable error.
- HEAD mismatch produces an error.

### T7 — `main` snapshots

Files: `hooks/available.lua`, `hooks/pre_install.lua`.

Acceptance:

- `mise ls-remote flutter` shows one `main-<12>` entry when the API works.
- `mise install flutter@main` resolves to it.
- `mise outdated`/`mise upgrade --dry-run` recognizes a newer snapshot.
- API failure hides the snapshot and does not break stable.

### T8 — Dart bootstrap + `MiseInstallSatisfied`

Files: `hooks/post_install.lua`, `hooks/mise_install_satisfied.lua`,
`lib/install.lua`.

Acceptance:

- `bootstrap = true` runs the command, writes `bootstrapped = true`, and
  populates the actual Dart version (test with the fixture by stubbing the
  command? Use a real Flutter SDK for this check in L3).
- `bootstrap = false` never invokes Flutter.
- Changing `bootstrap` from false to true causes `PostInstall` to rerun
  without a download.
- Bootstrap failure emits the stderr and the hint.

### T9 — Tests and CI

Files: `tests/integration.sh`, fixtures, `.github/workflows/ci.yml`,
`mise-tasks/`.

Acceptance:

- `bash tests/integration.sh` passes locally on macOS with isolated env.
- CI fixture matrix passes on Ubuntu, macOS and Windows.
- Real-index job writes a cross-platform lockfile.

### T10 — README and release polish

Files: `README.md`, `docs/`, `LICENSE`.

Acceptance:

- README follows §13.
- Install commands use the real repository URL.
- All examples work.
- No secrets, no local paths, no `TODO` placeholders.

### Definition of done

- [ ] `mise ls-remote flutter` works on macOS, Linux and Windows.
- [ ] `stable`, `beta`, `main`, `git-<sha>` and exact installs work.
- [ ] Official SHA-256 is verified; a tampered fixture fails.
- [ ] `dart --version` matches Flutter's bundled Dart.
- [ ] `mise lock` records URLs/checksums for archive-backed versions.
- [ ] `mise uninstall`, `mise prune`, `mise install --force` work.
- [ ] Paths with spaces work.
- [ ] CI is green; nightly workflow exists.
- [ ] README and docs are accurate, with no machine-specific paths.
- [ ] `stylua --check` passes; no shellcheck/actionlint errors.
- [ ] Working tree contains no `.scratch/`, build artifacts or tokens.

---

## 13. README requirements

The README must contain these sections, in this order:

1. **Title and one-line description**, plus CI badge.
2. **Why this plugin** — a short comparison with the built-in
   `http:flutter` backend: channels, main, commits, Dart detection, official
   SHA-256.
3. **Requirements** — `mise` (tested version), Git, and the platform
   prerequisites (macOS Xcode CLT; Linux `curl git unzip xz-utils zip
   libglu1-mesa`; Windows Git for Windows). Note the disk footprint.
4. **Install**:
   ```toml
   [plugins]
   flutter = "https://github.com/Minessential/mise-flutter#v0.1.0"

   [tools]
   flutter = "stable"
   ```
   and the CLI form.
   Add: "Installing the plugin under the name `flutter` overrides mise's
   built-in `http:flutter` backend. To go back, `mise plugins uninstall
   flutter`."
   Add the name-collision note with `mise-plugins/mise-flutter`.
5. **Usage** — a table of `stable`, `beta`, `main`, `main-<sha>`,
   `git-<sha>`, exact, plus examples. Mention `--pin` / exact versions for
   reproducible CI.
6. **Dart** — explain the bundled Dart, `dart --version`, `DART_SDK`,
   `MISE_FLUTTER_DART_VERSION`, `bootstrap`, and the "do not install a separate
   dart tool" warning.
7. **Options** — a table with `bootstrap` (default false), `FLUTTER_STORAGE_BASE_URL`
   mirror, and any additional option actually implemented.
8. **Platforms** — macOS x64/arm64, Linux x64, Windows x64; arm64 limitations.
9. **Verification and security** — official SHA-256, Git commit verification,
   mirror caveat, locked mode caveat for Git installs.
10. **Lockfile** — example and the `--locked` limitation.
11. **Idiomatic version files** — `.flutter-version`, and `.fvmrc` only if
    implemented; show the setting.
12. **Upgrading** — `mise upgrade flutter`, `mise outdated`, channel checksum,
    main snapshot pruning.
13. **Troubleshooting** — antivirus quarantine, Dart shim conflict, Rosetta,
    Linux arm64, GitHub rate limit, proxy/mirror, disk space, `flutter
    precache`.
14. **Development** — isolated test command, `mise run ci`, fixture tests.
15. **License** — MIT.

Tone: concise, factual, no marketing claims that are not tested. Every command
in the README must be runnable as written.

---

## 14. Risks and open decisions

| Risk | Impact | Mitigation |
| --- | --- | --- |
| mise changes vfox hook behavior | Plugin breaks | Pin/test against a known mise version in CI; keep hooks thin |
| GitHub API rate limit | No `main` snapshots | Fallback to `main` clone; document `MISE_GITHUB_TOKEN` |
| 2 GB archives + 600 MB bootstrap in CI | Slow/flaky nightly | Cache, nightly-only, `bootstrap = false` by default |
| Windows `.bat` shim behavior | `flutter`/`dart` not found | Windows fixture + nightly tests; explicit `.bat` checks |
| `mise exec -- dart` shadowing | Wrong Dart | README warning; PATH ordering; tests |
| Locked mode with Git installs | `--locked` fails | Document; archive path for released commits |
| Mirror checksums | Weaker trust | Visible README caveat; default official |
| Name collision with asdf plugin | User installs the wrong plugin | Full URL in README; explicit note |
| Antivirus quarantine on Windows | Missing `flutter.bat` | Actionable error message; README troubleshooting |
| Flutter archive layout changes | Broken extraction assumptions | Verify `bin/flutter` after install; tests against two versions |

Open decisions for the implementer (record the choice in
`docs/IMPLEMENTATION-NOTES.md`):

1. Whether `ParseLegacyFile` supports `.fvmrc` in v1 or only
   `.flutter-version`. Default: only `.flutter-version`; `.fvmrc` is P2.
2. Whether `MiseInstallSatisfied` also verifies the Git HEAD against the marker.
   Default: no (avoid Git at every install decision); verify during
   `PostInstall`.
3. Whether the fixture archives are committed binaries or generated by a
   script. Default: committed, under 50 KB each, with a generation script
   recorded for reproducibility.
4. Whether `Available` returns a `main` literal as a last-resort entry. Default:
   no; rely on exact-version pass-through and document the fallback.

---

## Appendix A — Command reference

```sh
# Isolated manual testing
export MISE_CONFIG_DIR="$PWD/.tmp/config"
export MISE_DATA_DIR="$PWD/.tmp/data"
export MISE_CACHE_DIR="$PWD/.tmp/cache"
export MISE_STATE_DIR="$PWD/.tmp/state"
export MISE_SYSTEM_CONFIG_DIR="$PWD/.tmp/system"
mise plugins link flutter "$PWD"
mise ls-remote flutter
mise use flutter@stable
mise exec -- flutter --version

# Fixture server
python3 -m http.server 8765 --directory tests/fixtures/storage &
export FLUTTER_STORAGE_BASE_URL="http://127.0.0.1:8765"

# Cross-platform resolution without downloads
mise lock --platform macos-arm64,macos-x64,linux-x64,windows-x64

# Debug
MISE_DEBUG=1 mise install flutter@stable
mise cache clear flutter
```

## Appendix B — Data snippets

Official index entry fields (macOS arm64, stable 3.47.9):

```json
{
  "hash": "c197ca5199e9ee5661e865596c9c07294dfab51c",
  "channel": "stable",
  "version": "3.47.9",
  "dart_sdk_version": "3.13.7",
  "dart_sdk_arch": "arm64",
  "release_date": "2026-10-29T19:11:44.648395Z",
  "archive": "stable/macos/flutter_macos_arm64_3.47.9-stable.zip",
  "sha256": "6545b8..."
}
```

`flutter.version.json` after bootstrap:

```json
{
  "frameworkVersion": "3.47.9",
  "channel": "stable",
  "repositoryUrl": "https://github.com/flutter/flutter.git",
  "frameworkRevision": "c197ca5199e9ee5661e865596c9c07294dfab51c",
  "engineRevision": "...",
  "dartSdkVersion": "3.13.7",
  "devToolsVersion": "...",
  "flutterVersion": "3.47.9"
}
```
