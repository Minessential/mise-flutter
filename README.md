# mise-flutter

A [mise](https://mise.jdx.dev) tool plugin for the Flutter SDK.

> **Status: specification phase.** The implementation is being written from
> [`docs/DESIGN.md`](docs/DESIGN.md). The README will be replaced before the
> first release.

## What it will support

- `stable`, `beta` and `main` channels
- Exact stable/beta versions
- A specific Flutter Git commit
- macOS (x64 and arm64), Linux (x64), Windows (x64)
- Automatic detection of Flutter's bundled Dart SDK
- Official SHA-256 verification from Flutter's release index
- One Lua tool plugin for every channel and install kind

## Documentation

- [Development specification](docs/DESIGN.md)
- [Research notes](docs/RESEARCH.md)

## Development

The plugin uses mise's Lua tool plugin API (`metadata.lua` + `hooks/`).
Testing must use isolated `MISE_*` directories; see the specification.

## License

MIT
