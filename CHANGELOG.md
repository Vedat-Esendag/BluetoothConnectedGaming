# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- BLE GATT profile (#8, ADR-0006): a shared `GattContract` (service +
  state/input characteristic UUIDs) that the host (#7) and joiner (#8) agree on,
  with the host advertising the service UUID so the joiner can discover it.
- BLE joiner core (#8): a `BleScanner` interface and a `JoinController` state
  machine (scan → connect → discover) with a sealed `JoinState` and a
  `JoinFailureReason` taxonomy, fully unit-tested with `mocktail` (no hardware).
- BLE joiner adapter (#8): `FlutterBluePlusScanner`, the hardware-backed
  `BleScanner` that scans by service UUID, connects, and verifies the contract's
  characteristics. Isolated behind the interface; validated on-device (#26),
  not in CI.
- Join screen (#8): a minimal `JoinScreen` (scan → host list → connect) reached
  from the home shell via "Join a Bluetooth game", rendering a specific message
  and recovery action for every outcome (success and each failure), with
  screen-reader labels and icon+text (never colour-only) status.
- BLE testing & debugging strategy (#37): `docs/testing-ble.md` capturing the
  recommended dev loop, the tools to install, and the split between automated
  tests (no hardware) and manual two-device verification — plus ADR-0007
  recording a fake/loopback `PeerTransport` (in `test/`) as the no-hardware test
  seam (implementation tracked by #11).
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
- Pool simulation core (#19, ADR-0008): `forge2d` as a direct dependency and a
  headless, role-agnostic `PoolSimulation` (cue + 15 balls, rails, pockets) that
  steps deterministically with no Flame import, plus plain-Dart `ShotCommand`
  and `PoolSnapshot` value types. Covered by a determinism test (same inputs →
  identical snapshots, per ADR-0003) and rack/strike/rest tests.

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

### Fixed
- The `PeerTransport` doc comment named `flutter_nearby_connections` as the v1
  backend; corrected to raw BLE via `flutter_blue_plus`, which ADR-0002 records as
  the v1 transport (`flutter_nearby_connections` was deferred and removed in
  ADR-0004).
