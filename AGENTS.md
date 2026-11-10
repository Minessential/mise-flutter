# AGENTS.md

Instructions for coding agents working in this repository.

## Read this first

1. [`docs/DESIGN.md`](docs/DESIGN.md) — the implementation contract.
2. [`docs/RESEARCH.md`](docs/RESEARCH.md) — verified mise/Flutter behavior and
   the evidence behind the design.

Do not re-research the basics; the documents already contain the API details,
field names, URLs, platform rules and expected behaviors. If something in the
spec is wrong or impossible, record it in `docs/IMPLEMENTATION-NOTES.md` and
explain the deviation instead of silently changing the design.

## Hard rules

- **Do not modify the user's global mise state.** Every command that touches
  mise must use isolated directories:

  ```sh
  export MISE_CONFIG_DIR="$PWD/.tmp/config"
  export MISE_DATA_DIR="$PWD/.tmp/data"
  export MISE_CACHE_DIR="$PWD/.tmp/cache"
  export MISE_STATE_DIR="$PWD/.tmp/state"
  export MISE_SYSTEM_CONFIG_DIR="$PWD/.tmp/system"
  ```

  Never run `mise use -g`, `mise plugins install` without isolation, or
  `mise self-update`.

- **Do not download multi-gigabyte Flutter archives** for routine testing. Use
  the local fixture server and `mise lock`. A real install is allowed only when
  the task explicitly asks for it, and then use an isolated `MISE_DATA_DIR`.

- **Do not commit or push.** Leave the changes in the working tree for review.
  Do not create tags or GitHub releases.

- **Do not print secrets.** Do not read `~/.pi`, `~/.config`, `auth.json`, or
  environment variables containing tokens. Do not add tokens to files, URLs or
  logs.

- **Stay in the repository.** Do not write outside the repository except
  temporary directories created by tests and removed by them.

## Implementation rules

- Lua 5.1 syntax only.
- Hooks are thin; business logic lives in `lib/`.
- Keep `metadata.lua` to assignments.
- Validate every version/commit string before using it in a URL or a shell
  command.
- Official archives: always return the official `sha256` from the release
  index. Never return a URL without a checksum.
- Git installs: verify `git rev-parse HEAD` equals the requested full SHA.
- Use `cmd.exec` with `cwd`; never build `cd ... && ...` strings.
- No `os.execute`.
- Do not modify files outside the install root, except the plugin cache.
- Tests must be deterministic and must not depend on a particular latest Flutter
  release; pin fixture versions and one real version (e.g. `3.47.9`).

## Commands

```sh
# format
stylua metadata.lua hooks lib tests

# fixture integration tests
bash tests/integration.sh

# all checks
mise run ci
```

## Definition of done

See the checklist at the end of `docs/DESIGN.md` §12. In addition:

- `git status` shows only intended files.
- No `.tmp/`, `.scratch/`, downloaded archives or generated lockfiles are
  staged.
- `docs/IMPLEMENTATION-NOTES.md` records any deviation and the reason.
