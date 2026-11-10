# Task for the implementer

You are implementing `mise-flutter`, a mise Lua tool plugin for the Flutter SDK.
The contract is [`DESIGN.md`](./DESIGN.md); the evidence is
[`RESEARCH.md`](./RESEARCH.md); the working rules are
[`../AGENTS.md`](../AGENTS.md).

## Goal

Deliver a working `v0.1.0` of the plugin and its tests/documentation. The
repository should be ready to tag and publish, but do **not** commit, tag or
push; leave the changes in the working tree.

## Order of work

Follow §12 of the design ("Implementation plan for pi"):

1. Scaffold (`metadata.lua`, hooks, lib, license, mise config).
2. Shared release/request/platform library.
3. `Available` (stable, beta, exact versions, `main-<sha>` snapshots).
4. `PreInstall` for official archives with the official SHA-256.
5. `PostInstall` for archives, marker file.
6. `EnvKeys` for Flutter and bundled Dart.
7. Git installs (`git-<sha>`, released commits use archives).
8. `main` snapshot install and upgrade behavior.
9. Optional Dart bootstrap + `MiseInstallSatisfied`.
10. Fixture integration tests + CI.
11. README and release polish.

Do not skip a step's acceptance check. If a check cannot run in this
environment, say so in `docs/IMPLEMENTATION-NOTES.md` and add the CI job that
will run it.

## Non-negotiable behaviors

- One plugin handles `stable`, `beta`, `main`, `main-<sha>`, `git-<sha>` and
  exact versions.
- Official archives always use the `sha256` from `releases_<os>.json`; a
  tampered archive must fail.
- Git installs must check out the exact requested commit and verify
  `git rev-parse HEAD`.
- `<root>/bin` on `PATH` must make both `flutter` and `dart` work on Unix and
  Windows.
- Linux arm64 and Windows arm64 native installs must produce a clear error
  (Windows arm64 may use x64 emulation only if the design says so).
- No `os.execute`; no shell string building with untrusted values.
- No writes outside the install root and the plugin cache.

## Testing

- Use isolated `MISE_*` directories for every mise command (see AGENTS.md).
- Build the local fixture server and tiny fake archives described in §10.3.
- `bash tests/integration.sh` must pass locally before you finish.
- Do not download a real Flutter SDK unless explicitly testing L3; if you do,
  use an isolated `MISE_DATA_DIR` and report the time/disk used.
- Add the CI workflow and nightly job from §11.2.

## Deliverables

- `metadata.lua`, `hooks/*.lua`, `lib/*.lua`
- `tests/integration.sh`, `tests/fixtures/**`
- `mise.toml`, `mise-tasks/*`, `.github/workflows/ci.yml`
- `README.md`, `LICENSE`, `docs/IMPLEMENTATION-NOTES.md`
- Any deviation from the design, documented with the reason

## Definition of done

Use the checklist at the end of §12. Report:

- what was implemented;
- what was tested, on which OS, and the commands/results;
- what was not tested and why;
- any deviations or open questions.
