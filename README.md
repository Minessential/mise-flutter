# mise-flutter

[![CI](https://github.com/Minessential/mise-flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/Minessential/mise-flutter/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A [mise](https://mise.jdx.dev) tool plugin for the Flutter SDK.

- `stable`, `beta` and `main` channels
- Exact stable/beta versions
- A specific Flutter Git commit
- macOS (x64 and arm64), Linux (x64), Windows (x64)
- Automatic detection of Flutter's bundled Dart SDK
- Official SHA-256 verification from Flutter's release index

One Lua tool plugin handles every channel and install kind. There is no second
install script to keep in sync.

## Why this plugin

mise has a built-in `http:flutter` backend that installs stable Flutter
releases. This plugin adds the parts that need channel- and Git-aware logic:

| | Built-in `http:flutter` | this plugin |
| --- | --- | --- |
| Stable releases | yes | yes |
| Beta channel | no | yes |
| `main` branch | no | yes, immutable snapshots |
| Arbitrary Git commit | no | yes |
| Official SHA-256 | backend-dependent | yes, from Flutter's release index |
| Bundled Dart detection | no | yes |
| Per-platform lockfile URLs/checksums | stable only | archive-backed versions |

Installing the plugin under the name `flutter` overrides the built-in backend
for that mise installation or project. See [Install](#install).

> This project is not the asdf plugin at
> [`mise-plugins/mise-flutter`](https://github.com/mise-plugins/mise-flutter).
> The install name is the same (`flutter`), but the URLs and implementations are
> different.

## Requirements

- **mise 2026.11.4 or newer** (tested with 2026.11.4).
- **Git** for `main` and commit installs, and for Flutter itself.
- **Disk space**: a Flutter archive is roughly 1.6–2.3 GB compressed. The
  first `flutter` or `dart` command downloads about 600 MB more into the SDK's
  `bin/cache`. Reserve at least 5 GB free.
- **Platform prerequisites** (same as a manual Flutter install):
  - macOS: Xcode command-line tools (`xcode-select --install`).
  - Linux: `curl`, `git`, `unzip`, `xz-utils`, `zip`, `libglu1-mesa`. On
    Debian/Ubuntu:
    `sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa`.
  - Windows: [Git for Windows](https://git-scm.com/downloads/win).
- **Python 3.11+** only for the repository's fixture tests; not needed to use
  the plugin.

## Install

Declare the plugin and the Flutter version in `mise.toml`:

```toml
[plugins]
flutter = "https://github.com/Minessential/mise-flutter#v0.1.0"

[tools]
flutter = "stable"
```

```sh
mise install
```

Or from the command line:

```sh
mise plugins install flutter 'https://github.com/Minessential/mise-flutter#v0.1.0'
mise use -g flutter@stable
```

Pinning the plugin to a tag (`#v0.1.0`) or a full commit SHA is recommended. A
branch moves; a tag or commit does not.

### Reverting to the built-in backend

Removing the plugin makes mise fall back to its registry backend:

```sh
mise plugins uninstall flutter
```

`mise plugins uninstall --purge flutter` also removes the Flutter versions
installed by the plugin.

## Usage

| Request | What it installs |
| --- | --- |
| `flutter@latest` | newest stable numeric release |
| `flutter@stable` | current stable channel, rolling |
| `flutter@beta` | current beta channel, rolling |
| `flutter@3.47.9` | that exact stable release |
| `flutter@3.50.0-0.4.pre` | that exact beta release |
| `flutter@main` | newest `main` snapshot |
| `flutter@main-20261110062038-fffd8c22ae64` | a pinned `main` snapshot |
| `flutter@git-c197ca5199e9ee5661e865596c9c07294dfab51c` | that commit |

```sh
mise use flutter@stable
mise use flutter@beta
mise use flutter@3.47.9
mise use flutter@main
mise use flutter@git-c197ca5199e9ee5661e865596c9c07294dfab51c

mise exec -- flutter --version
mise exec -- dart --version
```

`latest` is the newest stable numeric release. Beta versions are prereleases,
so mise hides them from `ls-remote` and `latest`; use the `beta` channel or the
full exact version.

### Channels

`stable` and `beta` are rolling channel directories:

```sh
mise upgrade flutter          # moves a channel to the current release
mise outdated                 # reports a changed channel
mise install --force flutter@stable
```

The plugin returns the official archive SHA-256 for the current platform as the
channel checksum, so mise can detect a channel change and verify the download.

Use an exact version when you need a byte-for-byte pin:

```toml
[tools]
flutter = "3.47.9"
```

### `main` snapshots

`main` (the Flutter `master` branch) has no official archive. The plugin lists
one snapshot per current head:

```text
main-<UTC commit time>-<first 12 hex of the commit>
main-20261110062038-fffd8c22ae64
```

The timestamp prefix is deliberate: mise orders versions as strings, so a
timestamp makes newer snapshots compare higher. Without it, a snapshot whose
commit hash happens to sort lower would be reported as up to date. Snapshots
are development builds, so they are not hidden by `minimum_release_age`; the
timestamp is ordering metadata, not a release date.

```sh
mise use flutter@main
mise ls-remote flutter | grep '^main-'
mise outdated
mise upgrade flutter
```

Snapshots install a shallow Git checkout and verify `git rev-parse HEAD`.
`flutter --version` reports `0.0.0-unknown` for a tagless shallow checkout;
that is expected. Use `stable`, `beta`, or a released commit when you need a
real framework version string.

If the GitHub API is unavailable, `mise install flutter@main` falls back to a
`main` directory resolved with `git ls-remote`. That fallback is for
availability, not reproducibility; automatic upgrade detection is not
guaranteed for it. Prefer a `main-<timestamp>-<sha>` pin in CI.

### Git commits

`git-<sha>` accepts 7 to 40 hexadecimal characters (full SHA recommended):

```sh
mise use flutter@git-c197ca5199e9ee5661e865596c9c07294dfab51c
```

- If the commit is a published stable/beta release, the plugin installs the
  official archive for it and verifies Flutter's official SHA-256. The install
  is byte-for-byte the released SDK, even though the directory is named
  `git-<sha>`.
- Otherwise it performs a shallow fetch of exactly that commit, verifies
  `git rev-parse HEAD`, and installs a Git checkout. There is no official
  archive checksum in this case; the commit SHA is the integrity check.
- Short SHAs are resolved through the GitHub API. The commit must be reachable
  from `flutter/flutter`.

## Dart

Flutter ships its own Dart SDK wrapper at `<flutter>/bin/dart`
(`dart.bat` on Windows). Putting `<flutter>/bin` on `PATH` gives you a Dart
that always matches the selected Flutter version.

The plugin sets:

| Variable | Value |
| --- | --- |
| `FLUTTER_ROOT` | the Flutter SDK directory |
| `PATH` | `<flutter>/bin` |
| `DART_SDK` | `<flutter>/bin/cache/dart-sdk`, once it exists |
| `MISE_FLUTTER_DART_VERSION` | the actual Dart version, or the index's expected version when known before the SDK is downloaded |
| `MISE_FLUTTER_REVISION` | the release hash or Git commit |
| `MISE_FLUTTER_CHANNEL` | `stable`, `beta`, `main`, or `unknown` |

### Lazy by default

`bootstrap` defaults to `false`. `mise install` only downloads and extracts the
Flutter SDK. The first `flutter` or `dart` command downloads the matching Dart
SDK into `bin/cache` (about 600 MB) and builds the Flutter tool. This is
Flutter's normal behavior.

### Pre-provisioning

Set `bootstrap = true` to run `flutter --version --machine` during install and
fail the install if the Dart SDK cannot be bootstrapped:

```toml
[tools]
flutter = { version = "stable", bootstrap = true }
```

The bootstrap runs with `HOME`, `PUB_CACHE`, `XDG_CONFIG_HOME`, `APPDATA` and
`LOCALAPPDATA` redirected inside the install directory, so it does not populate
your user-level pub cache or Flutter config. It does **not** run
`flutter precache`; Android/iOS/web engine artifacts remain a per-project step:

```sh
mise exec -- flutter precache --universal
```

### Do not install a separate Dart tool

Do not configure mise's `dart` backend alongside this plugin: you would get two
Dart SDKs that can drift apart. Flutter's `bin/dart` is the one you want.

If `mise exec -- dart --version` complains about a shim, a `dart` tool is still
configured. Remove it from your mise config and use `flutter` only.

## Configuration

### Tool options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `bootstrap` | boolean | `false` | Download the bundled Dart SDK during install |

### Environment

| Variable | Description |
| --- | --- |
| `FLUTTER_STORAGE_BASE_URL` | Storage root for the release index and archives. Default: `https://storage.googleapis.com`. A mirror such as `https://storage.flutter-io.cn` works if it has the Flutter layout. |
| `MISE_GITHUB_TOKEN` / `GITHUB_TOKEN` | Raises GitHub API rate limits for `main` snapshots and short SHA resolution. mise can also reuse a `gh` login. |

When a mirror is used, the checksums come from that mirror's release index.
The default official host is recommended for strict verification.

### Idiomatic version file

`.flutter-version` is supported. It holds a single request, such as `stable` or
`3.47.9`:

```text
3.47.9
```

```toml
[settings]
idiomatic_version_file_enable_tools = ["flutter"]
```

## Platforms

| Platform | Support |
| --- | --- |
| macOS arm64 | native arm64 archive; x64 fallback under Rosetta for old releases |
| macOS x64 | x64 archive |
| Linux x64 | x64 archive |
| Windows x64 | x64 archive |
| Linux arm64 | not supported by Flutter; the plugin stops with a clear error |
| Windows arm64 | x64 SDK under Windows emulation (best effort, warning) |

The CI fixture matrix runs on Ubuntu, macOS and Windows. Real Flutter installs
run in the nightly/manual workflow because each one downloads 1.6–2.3 GB.

## Verification and security

- **Official archives**: the plugin returns the `sha256` published in
  `releases_macos.json`, `releases_linux.json` or `releases_windows.json`.
  mise verifies it before extraction. A missing or malformed checksum is an
  error; the plugin never returns an archive URL without one.
- **Git installs**: the plugin fetches the exact full commit and checks
  `git rev-parse HEAD`. It never invents an archive checksum for a Git checkout.
- **Mirrors**: `FLUTTER_STORAGE_BASE_URL` changes both the index and the
  download host, so the checksum trust moves with the mirror. Use the official
  host if that matters.
- **Shell safety**: versions and commit identifiers are validated before use;
  paths are never pasted into `cd ... && ...` commands.

## Lockfile

Archive-backed versions can be locked per platform:

```sh
mise lock --platform macos-arm64,macos-x64,linux-x64,windows-x64
mise install --locked
```

For exact versions and released commits, `mise.lock` records the per-platform
URL and checksum, and locked installs verify them.

Known limitations on mise 2026.11.4:

- A rolling channel (`stable`/`beta`) stores a checksum, but `mise install
  --locked` may re-resolve the channel against the current index. Use an exact
  version when strict byte pinning matters.
- A Git-only install (`main` snapshot or unreleased commit) has no artifact URL
  or checksum, so locked mode cannot verify its bytes. The commit SHA in the
  version string is the pin. For a lockable commit install, use
  `git-<sha>` for a published release.
- **Generating a lockfile can download archives.** On mise 2026.11.4,
  `mise lock --platform ...` hashed each platform's archive itself instead of
  using the checksum returned by `PreInstall`. Locking four platforms can
  therefore download several gigabytes. The plugin cannot prevent this. Run
  `mise lock` where bandwidth/disk allow, lock only the current platform, or
  rely on the official checksum at install time instead.

## Upgrading

```sh
mise outdated
mise upgrade flutter
mise install --force flutter@stable
mise uninstall flutter@stable
mise prune
```

Channels compare the archive checksum. `main` snapshots compare the
timestamped version string; old snapshots are pruned after mise's normal grace
period.

## Troubleshooting

**`bin/flutter` is missing after install**
On Windows, antivirus software sometimes quarantines `flutter.bat`. Configure
an exclusion for the mise install directory and reinstall. On other platforms,
the downloaded archive did not match the expected layout; run with
`MISE_DEBUG=1` and check the archive URL.

**`mise exec -- dart` reports a shim or wrong version**
A separate `dart` tool is configured. Remove it from `mise.toml`; use Flutter's
bundled Dart instead. `mise exec -- sh -c 'dart --version'` bypasses mise's
tool routing for a quick check.

**The install fails with `Dart SDK bootstrap failed`**
Only happens with `bootstrap = true`. Check network access to `pub.dev`, set
`PUB_HOSTED_URL` if you use a pub mirror, or install with `bootstrap = false`
and let Flutter bootstrap on first use.

**macOS says the SDK is x64 on Apple Silicon**
Older Flutter releases have no arm64 archive. The plugin falls back to x64
under Rosetta and prints a warning. Install Rosetta (`softwareupdate
--install-rosetta`) or use a newer release.

**Linux arm64**
Flutter does not publish Linux arm64 SDKs. Use an x64 machine, or wait for
official support.

**GitHub API rate limit**
Set `MISE_GITHUB_TOKEN` (or `GITHUB_TOKEN`) to raise the limit. Without a token,
`main` snapshots may be omitted and short SHA resolution may fail; stable/beta
installs still work.

**Downloads are slow or blocked**
Set `FLUTTER_STORAGE_BASE_URL` to a mirror with the same layout. Remember the
mirror trust caveat above.

**Disk space**
Archives are large, and mise keeps downloads. Use `mise cache clear` to clear
cached downloads after you no longer need them.

## Development

The repository has three test layers:

- `tests/integration.sh` — deterministic local fixture server and tiny archives.
  No Flutter download.
- `tests/real-index.sh` — live release index and cross-platform `PreInstall`
  resolution. Blocks SDK downloads.
- `tests/real-install.sh` — downloads a real Flutter SDK. Intended for the
  nightly/manual CI job.

```sh
export MISE_CONFIG_DIR="$PWD/.tmp/config"
export MISE_DATA_DIR="$PWD/.tmp/data"
export MISE_CACHE_DIR="$PWD/.tmp/cache"
export MISE_STATE_DIR="$PWD/.tmp/state"
export MISE_SYSTEM_CONFIG_DIR="$PWD/.tmp/system"

mise plugins link flutter "$PWD"
mise ls-remote flutter
bash tests/integration.sh
mise run ci
```

The fixture tests require Python 3.11+. The design and research notes are in
[`docs/DESIGN.md`](docs/DESIGN.md), [`docs/RESEARCH.md`](docs/RESEARCH.md), and
[`docs/IMPLEMENTATION-NOTES.md`](docs/IMPLEMENTATION-NOTES.md).

## License

MIT. See [LICENSE](LICENSE).
