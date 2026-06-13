# NearPlay

> A collection of bite-sized mini-games you play **together, offline, over Bluetooth**. Pull out two phones, pick a game, and play — pool, and more to come.

[![CI](https://github.com/Vedat-Esendag/BluetoothConnectedGaming/actions/workflows/ci.yml/badge.svg)](https://github.com/Vedat-Esendag/BluetoothConnectedGaming/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter)

## What this is

NearPlay is a single Flutter app that hosts **many independent mini-games** behind one shared interface. Two players on the same Wi-Fi/Bluetooth range connect device-to-device — no server, no internet, no accounts. The first game is **Pool** (real ball physics via forge2d).

## Architecture in one paragraph

Every mini-game is a self-contained module under `lib/games/<id>/` that exposes a single `MiniGameDescriptor`. The shell discovers games through a registry and never imports game internals, so adding a game is additive — it can't break the others. Local multiplayer goes through one `PeerTransport` abstraction; games never touch the concrete Bluetooth backend. **Nothing that arrives over the wire is trusted** — every inbound packet is validated before the app sees it, because there is no server to sanitize input for us. Full detail in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Getting started

See **[SETUP.md](SETUP.md)** for the exact, ordered command sequence (create project, add deps, wire up Claude Code, push to GitHub).

## How we work

Development runs as a loop inside Claude Code — decide, build, review, gate, ship — backed by the repo as the single source of truth. The rules live in [CLAUDE.md](CLAUDE.md); the contributor workflow is in [CONTRIBUTING.md](CONTRIBUTING.md); decisions are recorded as ADRs in [docs/adr/](docs/adr/).

## Roadmap

Mini-games are tracked as milestones. Start: Pool (2P, host-authoritative physics). Next candidates: air hockey, reaction duel, tic-tac-toe, dots-and-boxes. Cross-OS (iPhone ⇄ Android) Bluetooth play is a dedicated later milestone — see [docs/adr/0002](docs/adr/0002-multiplayer-transport-and-scope.md).

## License

MIT — see [LICENSE](LICENSE). Swap this if you decide to distribute differently.
