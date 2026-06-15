# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- BLE GATT profile (#8, ADR-0006): a shared `GattContract` (service +
  state/input characteristic UUIDs) that the host (#7) and joiner (#8) agree on,
  with the host advertising the service UUID so the joiner can discover it.
- Peer message protocol (#12): a `MessageType` vocabulary
  (`handshake`/`input`/`state`/`ping`) as the canonical source for wire types,
  a wire protocol version field validated in `PeerMessage.fromWire`, and
  round-trip tests for every type. The issue's "move" is realized as `input`
  (see ADR-0005).
- Project scaffold: mini-game registry, `PeerTransport` abstraction, validated
  `PeerMessage`, Pool descriptor stub.
- Engineering setup: CLAUDE.md, review subagents, hooks, CI, ADRs.
- `CONTRIBUTING.md`: branch/PR flow, Conventional Commits, review gates,
  `/new-minigame`, and the definition of done.

### Changed
- Adopt `package:` imports and clear all `very_good_analysis` findings.
- Align naming: package stays `bluetooth_connected_gaming`; the product display
  name is **NearPlay** (resolved in #18), and README badges point at the repo.
- Scope Git LFS to `assets/`; keep platform launcher icons in normal git so the
  iOS/Android CI builds can read them.

### Removed
- Unused `equatable` dependency.
- `flutter_nearby_connections` dependency — deferred until the transport is
  implemented; it does not build under AGP 8.11 / Kotlin 2.2 yet (see ADR-0004).
