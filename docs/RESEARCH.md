# Research notes: a Flutter plugin for mise

Status: research complete, 2026-11-10
Environment used for the experiments: mise 2026.11.4 (macOS arm64), Flutter
release index data as published on 2026-11-10, GitHub API for `flutter/flutter`.

This document records what was verified, where the facts come from, and why the
design in [`DESIGN.md`](./DESIGN.md) looks the way it does. It is intentionally
separate from the specification so the specification can stay stable while the
evidence stays auditable.

## 1. Method

- Read the current mise plugin documentation from the `jdx/mise` repository
  (raw Markdown, not the rendered site) and the corresponding Lua reference.
- Read the relevant mise source: version resolution, rolling-channel handling,
  vfox install flow, checksum storage, and lockfile behavior.
- Inspected the live Flutter release indexes for macOS, Linux and Windows.
- Inspected the Flutter SDK layout and bootstrap scripts from an installed SDK
  and from a shallow Git checkout of `flutter/flutter`.
- Ran small, disposable tool plugins against an isolated `MISE_*` environment to
  verify resolution, install-hook, environment and upgrade behavior.
- Reviewed the existing community plugins (`mise-plugins/mise-flutter`,
  `jdx/vfox-flutter`) and the built-in `http:flutter` registry entry.

All experiments used isolated `MISE_CONFIG_DIR`, `MISE_DATA_DIR`,
`MISE_CACHE_DIR`, `MISE_STATE_DIR` and `MISE_SYSTEM_CONFIG_DIR` directories.
No global mise configuration was modified.

## 2. Sources

### mise

| Topic | Source |
| --- | --- |
| Tool plugin hooks and options | <https://mise.jdx.dev/tool-plugin-development.html> |
| Backend plugin hooks | <https://mise.jdx.dev/backend-plugin-development.html> |
| Lua modules, `RUNTIME`, metadata | <https://mise.jdx.dev/plugin-lua-modules.html> |
| Publishing and installation | <https://mise.jdx.dev/plugin-publishing.html> |
| Plugin install/precedence rules | <https://mise.jdx.dev/plugins.html> |
| Version requests (`latest`, prefixes, prereleases) | <https://mise.jdx.dev/dev-tools/versions.html> |
| Lockfile and per-backend capabilities | <https://mise.jdx.dev/dev-tools/mise-lock.html> |
| Built-in HTTP backend | <https://mise.jdx.dev/dev-tools/backends/http.html> |
| GitHub tokens in plugins | <https://mise.jdx.dev/dev-tools/github-tokens.html> |
| Tool plugin template | <https://github.com/jdx/mise-tool-plugin-template> |
| Generated version list for `http:flutter` | <https://mise-versions.jdx.dev/data/flutter.toml> |
| mise regression test for Flutter URLs | <https://github.com/jdx/mise/blob/main/e2e/backend/test_http_flutter_url> |
| Source: rolling channels | `src/toolset/tool_version.rs`, `src/toolset/outdated_info.rs`, `src/backend/mod.rs` |
| Source: checksum recording | `src/backend/vfox.rs`, `crates/vfox/src/vfox/install.rs` |
| Source: available-entry parsing | `crates/vfox/src/hooks/available.rs` |

### Flutter

| Topic | Source |
| --- | --- |
| Manual SDK install, prerequisites | <https://docs.flutter.dev/install/manual> |
| SDK archive, channel descriptions | <https://docs.flutter.dev/install/archive> |
| Channel semantics and branch names | <https://github.com/flutter/flutter/blob/master/docs/releases/Flutter-build-release-channels.md> |
| macOS archive layout and arm64 bundles | <https://docs.flutter.dev/install/manual> |
| Release index (macOS) | <https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json> |
| Release index (Linux) | <https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json> |
| Release index (Windows) | <https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json> |
| Flutter repository | <https://github.com/flutter/flutter> |
| Dart SDK download script | `bin/internal/update_dart_sdk.sh` in the SDK |

### Prior art

| Project | What it does | Gap for us |
| --- | --- | --- |
| Built-in `http:flutter` | Stable versions from `mise-versions`, HTTP download | No beta/main/commit, no Dart handling, no channel tracking |
| `mise-plugins/mise-flutter` (asdf) | Parses release JSON with `jq`, stable/beta channel hashes, macOS arch selection | Linux/macOS only, no main/commit, no Dart handling, `jq` dependency |
| `jdx/vfox-flutter` (Lua) | Resolves stable/beta/dev via `current_release`, returns official SHA-256 | No main/commit, no Dart handling, channel installs use the requested channel as the version directory |
| FVM | Project-level Flutter cache with channels and `.fvmrc` | Different tool, heavier; useful as a migration source |

## 3. Verified mise behavior

### 3.1 A Lua tool plugin can install an exact version that is not listed

`Available` returned only `3.0.0`, `2.0.0` and `main`, then:

```sh
mise install dummytool@9.9.9
```

succeeded and called `PreInstall` with `ctx.version = "9.9.9"`. `mise use
dummytool@git-abc1234` also succeeded and wrote `dummytool = "git-abc1234"` to
`mise.toml`.

Implication: arbitrary commit versions such as `git-<sha>` do not have to be
enumerated by `Available`. Only prefixes, `latest` and `main-<sha>` snapshots
need listing.

### 3.2 `PreInstall` cannot change the install directory name

When `PreInstall` returned `version = "8.8.8"` for a request of `9.9.9`, mise
still installed into `installs/dummytool/9.9.9` and `PostInstall` received
`rootPath = .../9.9.9`.

Implication: a channel request such as `flutter@stable` cannot be silently
installed as `installs/flutter/3.47.9` by returning a different version. The
design therefore uses either a stable channel directory (`stable`) or a
snapshot version string (`main-<sha>`).

### 3.3 A plugin named `flutter` overrides the built-in `http:flutter` backend

After `mise plugins link flutter ./dummy`, `mise ls-remote flutter` returned the
dummy plugin's versions instead of the built-in HTTP list. This is how users opt
into the plugin.

### 3.4 `latest` ignores channel entries and prereleases

`Available` returned `stable`, `beta`, `main-aaa1111`, `3.0.0` and `2.0.0`.
`mise latest dummytool` returned `3.0.0`; with `3.50.0-0.4.pre` present,
`mise latest` still returned the newest stable version (`3.47.9` in the
realistic test).

Prerelease versions are omitted from `mise ls-remote` by default. A short prefix
such as `3.50` does not resolve to a prerelease; request the exact full version
(`3.50.0-0.4.pre`) or use the `beta` channel.

Implication: channel entries do not pollute `latest`, and `Available` can put
them first.

### 3.5 `main-<sha>` snapshots upgrade correctly

With `Available` returning `main-aaa1111` and a request of `main`:

- `mise use dummytool@main` resolved to `main-aaa1111` and wrote
  `dummytool = "main"`.
- After `Available` changed to `main-bbb2222`, `mise outdated` reported
  `main -> main-bbb2222`.
- `mise upgrade --dry-run` said it would install `main-bbb2222` and prune
  `main-aaa1111` after 24 hours.

Implication: for the moving `main` branch, listing immutable snapshots is
better than a mutable `main` directory. It gives deterministic install
directories, normal upgrade/prune behavior, and no fake checksums.

Follow-up discovered during implementation: mise compares version strings, so a
bare `main-<shortsha>` can sort lower than an older installed snapshot even
when its commit is newer. The final design prefixes the UTC commit time:
`main-<YYYYMMDDHHMMSS>-<shortsha>`. The fixture suite covers both ascending and
descending hash orders.

### 3.6 Rolling channels use a stored checksum

`crates/vfox/src/hooks/available.rs` parses `rolling` and `checksum`.
`src/backend/vfox.rs` writes the `PreInstall` SHA-256 to
`<install>/.mise.checksum`. `Backend::is_rolling_version_outdated` compares that
stored value with the checksum of the current rolling entry.

Implication: `stable` and `beta` can be genuine rolling directories. `main-<sha>`
snapshots are immutable and need no rolling checksum.

### 3.7 Lockfile requirements differ by backend

From the lockfile documentation's backend table:

- vfox **tool** plugins record "URLs that the plugin's hooks return, which
  locked mode requires".
- vfox **backend** plugins record only the version.

A tool plugin that returns no URL for a git install therefore cannot satisfy
`mise install --locked` for that platform. Release archives can.

Implication: document full lockfile support for stable/beta/exact versions and
for commits that have an official release archive; document the limitation for
arbitrary commits and `main` snapshots.

### 3.8 Plugins have no hashing function

The Lua reference lists `http`, `json`, `file`, `archiver`, `cmd`, `strings`,
`semver`, `html`, `env`, `mise.cache` and `log`. There is no digest function.

Implication: the plugin must rely on mise to verify official SHA-256 values from
`PreInstall`, and use Git's content-addressed commit SHA for git checkouts. It
must not attempt to compute hashes in Lua.

### 3.9 `io.open` works in hooks; `file` has no write function

A `PostInstall` hook wrote a file with `io.open(path, "w")` and it was created
successfully. The `file` module only reads, stats, lists, moves and symlinks.

Implication: marker files can be written with `io.open`; the installed tree is
otherwise left untouched.

### 3.10 `EnvKeys` path entries create working shims

A test install with `EnvKeys` returning `PATH = <install>/bin` made
`mise exec dummytool@git-abc1234 -- fakeflutter --version` execute the binary
inside the install directory.

Implication: returning `<root>/bin` is enough for both `flutter` and `dart` on
Unix, and for `flutter.bat`/`dart.bat` on Windows (to be verified in the Windows
CI job).

### 3.11 A configured `dart` tool can shadow Flutter's bundled Dart

With a global `dart` shim present, `mise exec flutter@3.29.2 -- dart --version`
failed with "dart is not a valid shim", while
`mise exec flutter@3.29.2 -- sh -c 'dart --version'` printed the bundled Dart
version.

Implication: document that users should not configure a separate `dart` tool
when they rely on Flutter's bundled Dart. The plugin can put Flutter's `bin`
first, but mise's tool-name routing still intercepts `mise exec -- dart`.

### 3.12 Git checkout behavior for Flutter

A shallow fetch of one Flutter commit:

```sh
git init
git remote add origin https://github.com/flutter/flutter.git
git fetch --depth 1 origin c197ca5199e9ee5661e865596c9c07294dfab51c
git checkout --detach FETCH_HEAD
```

succeeded in ~29 s and took 223 MB on disk. Running
`bin/flutter --version --machine` then:

- downloaded/build the Dart SDK and Flutter tool (~671 MB in `bin/cache`),
- reported `frameworkVersion: "0.0.0-unknown"`, `channel: "[user-branch]"`,
  `dartSdkVersion: "3.13.7"` for the shallow, tagless checkout.

Implication: shallow git installs are practical and work, but Git-based installs
cannot report a real framework version without tags. Released commits should use
the official archive (which includes `.git`) instead. For `main` snapshots,
`0.0.0-unknown` is an honest result; document it.

### 3.13 Flutter's bundled Dart is a wrapper in `bin/`

The installed SDK has `bin/flutter`, `bin/flutter.bat`, `bin/dart` and
`bin/dart.bat`. `bin/dart` bootstraps and executes
`bin/cache/dart-sdk/bin/dart`. `bin/cache/flutter.version.json` contains
`frameworkVersion`, `channel`, `frameworkRevision`, `engineRevision` and
`dartSdkVersion`.

Implication: putting `<root>/bin` on `PATH` provides the correct Dart version
automatically, and Dart metadata is available from small files without network
access.

## 4. Flutter release index facts (2026-11-10)

### 4.1 Shape

Top-level keys: `base_url`, `current_release`, `releases`.

```json
{
  "base_url": "https://storage.googleapis.com/flutter_infra_release/releases",
  "current_release": {
    "beta": "368ac9e40bad0566927cc9428a42461152652c12",
    "dev": "13a2fb10b838971ce211230f8ffdd094c14af02c",
    "stable": "c197ca5199e9ee5661e865596c9c07294dfab51c"
  },
  "releases": [
    {
      "hash": "c197ca5199e9ee5661e865596c9c07294dfab51c",
      "channel": "stable",
      "version": "3.47.9",
      "dart_sdk_version": "3.13.7",
      "dart_sdk_arch": "x64",
      "release_date": "2026-10-29T19:11:44.648395Z",
      "archive": "stable/macos/flutter_macos_3.47.9-stable.zip",
      "sha256": "0dc38b4038a0b002a6258696a5b327a58473c175c9e334b9f329ef7d79a4fdcd"
    }
  ]
}
```

### 4.2 Counts and channels

| OS | Entries | Stable | Beta | Dev |
| --- | ---: | ---: | ---: | ---: |
| macOS | 1019 | 341 | 364 | 314 |
| Linux | 749 | 197 | 238 | 314 |
| Windows | 747 | 196 | 237 | 314 |

Every entry in all three indexes has a 64-character `sha256` (`0` missing,
`0` malformed at the time of checking).

### 4.3 Archives and architectures

| OS | Archive suffix | Architectures present |
| --- | --- | --- |
| macOS | `.zip` | x64 and arm64 bundles for modern versions; older versions only x64 |
| Linux | `.tar.xz` | x64 only |
| Windows | `.zip` | x64 only |

macOS versions can have two entries with the same `version`/`channel`: one
`..._macos_<ver>-stable.zip` (x64) and one
`..._macos_arm64_<ver>-stable.zip` (arm64). The `dart_sdk_arch` field is the
reliable selector when present; older entries omit it, so the archive name is
the fallback.

`dart_sdk_arch` is absent on 430/1019 macOS entries, 431/749 Linux entries and
431/747 Windows entries. The field must not be assumed.

### 4.4 Current releases

| Channel | Version | Dart | macOS archive |
| --- | --- | --- | --- |
| stable | 3.47.9 | 3.13.7 | `stable/macos/flutter_macos_3.47.9-stable.zip` |
| beta | 3.50.0-0.4.pre | 3.14.0 (build 3.14.0-315.3.beta) | `beta/macos/flutter_macos_3.50.0-0.4.pre-beta.zip` |

`dart_sdk_version` can contain a build suffix in beta entries. The plugin should
store it verbatim for display, and read the actual version file when it exists.

### 4.5 Archive sizes (stable 3.47.9)

| OS/arch | Compressed size |
| --- | ---: |
| macOS x64 | 2,267,357,571 bytes (~2.27 GB) |
| macOS arm64 | 2,268,740,583 bytes (~2.27 GB) |
| Linux x64 | 1,582,752,184 bytes (~1.58 GB) |
| Windows x64 | 1,939,451,626 bytes (~1.94 GB) |

Flutter installs are large. Tests must not download these on every pull request,
and the README must mention disk usage.

### 4.6 Installed SDK layout

An official archive extracts to a single top-level `flutter/` directory. mise
strips that directory, so the install root contains:

```text
bin/flutter
bin/flutter.bat
bin/dart
bin/dart.bat
bin/internal/engine.version
bin/internal/update_dart_sdk.sh
.git/
...
```

The `.git` directory is part of the official archive, so `flutter upgrade` and
`flutter channel` work from an archive install.

The `bin/cache/` directory (Dart SDK, Flutter tool snapshot, engine artifacts)
is **not** in the archive and is populated on first use.

## 5. Existing implementation observations

### 5.1 Built-in `http:flutter`

`mise ls-remote flutter` downloads
`https://mise-versions.jdx.dev/data/flutter.toml`, whose versions are stable
releases only (the generated list contains versions such as `3.47.9` and older
`v1.x` entries). There is no beta, main, commit or Dart logic. mise also has an
e2e regression test that asserts a request such as `flutter@3.22.1` resolves and
that the URL builder does not produce `...-stable-stable.tar.xz`.

Installing the plugin under the name `flutter` replaces this backend for that
user/project, which is the intended opt-in.

### 5.2 `mise-plugins/mise-flutter` (asdf)

- Uses `jq` downloaded at runtime.
- `list-all` appends `-<channel>` to each version.
- Resolves stable/beta through `current_release`.
- Selects macOS architecture with `dart_sdk_arch`.
- Does not support main or commits, does not detect Dart, and is Linux/macOS
  only.
- The GitHub repository name is identical to this project's intended name
  (different owner), so the README must disambiguate.

### 5.3 `jdx/vfox-flutter`

- Resolves channels in `PreInstall` by matching `current_release[channel]` to a
  release `hash`, then returns the archive URL and SHA-256.
- Sorts versions manually and returns extra vfox fields (`url`, `sha256`,
  `key`, `note`, `addition`), some of which mise ignores.
- No main/commit support and no Dart handling.

### 5.4 FVM

FVM stores project pins in `.fvmrc` (JSON, `flutter` key) and older versions in
`.fvm/fvm_config.json` (`flutterSdkVersion`). A future `ParseLegacyFile` hook
could read `.fvmrc`, but it is not required for v1.

## 6. Design implications

1. **Tool plugin, not backend plugin.** Only a tool plugin gets mise's download,
   checksum verification, lockfile URL recording, and Windows support.
2. **One plugin, two artifact providers.** Official archives cover stable,
   beta, latest and released commits; Git checkouts cover main snapshots and
   arbitrary commits. Request classification decides which provider is used.
3. **Channels as rolling directories; main as immutable snapshots.** `stable`
   and `beta` use `rolling = true` plus the archive SHA-256. `main` is exposed
   as `main-<timestamp>-<12-hex>` entries so normal prefix resolution, upgrades
   and pruning
   work.
4. **No hash function in Lua.** Official SHA-256 comes from the release index
   and is verified by mise. Git installs are verified by checking out an exact
   commit and asserting `git rev-parse HEAD`.
5. **Dart is bundled, not installed separately.** `<root>/bin` provides both
   executables, `<root>/bin/cache/dart-sdk` is the SDK, and env keys expose the
   detected version. Bootstrapping is optional.
6. **Fail closed.** Never return a URL without a checksum for an official
   archive; never continue after a checksum or HEAD mismatch.
7. **Distribution through `[plugins]`.** The mise registry does not accept new
   asdf/vfox-backed tools, so the README must show the repository URL.

## 7. Open questions carried into the design

- Whether `mise lock` accepts a URL-less entry for `main-<timestamp>-<sha>` in all current
  mise versions. The design documents the limitation rather than relying on it.
- Whether Windows mise creates shims for `.bat`-only tools in all supported
  versions. The Windows CI job must assert this.
- Whether a future mise release exposes a channel-resolution hook for vfox tool
  plugins (like `resolve_channel_version` for core backends). If it does, the
  `stable`/`beta` implementation can be simplified, but the current design works
  without it.
