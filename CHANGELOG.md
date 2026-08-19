# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Two-device multiplayer works end to end.** A lobby (#6) hosts or joins, a
  handshake (#13) exchanges names and confirms roles, and the resulting
  `GameSession` is handed to the game (#17) — the argument that had been
  ignored since it was added.
- Concrete `PeerTransport` (#16) over a byte-level `PeerConnection` (#10), with
  length-prefixed chunking and bounded reassembly (ADR-0010) so frames larger
  than a BLE MTU survive the trip.
- Replay protection (#29): per-peer sequence tracking and identity pinning,
  enforced in the transport rather than documented and unimplemented.
- BLE host role (#7): the host advertises, runs a GATT server, accepts writes
  and pushes notifications — and serves exactly one joiner. Raw bidirectional
  byte exchange (#9) is the same `PeerConnection` on both sides.
- `LoopbackPeerConnection` (#11) in `test/support/`: two peers in-process at a
  20-byte chunk size, so the whole stack above the radio is testable in CI.
- Pool multiplayer (#14, #20, #21, #23): the host simulates and broadcasts at
  20 Hz, the client renders and sends shots, turn state gates both devices'
  controls, and the winner card names the players.
- Real 8-ball rules (#22): group assignment on the first legal pot,
  first-contact and rail fouls observed by a forge2d contact listener, and a
  win condition that requires clearing your group before the 8. Ball-in-hand
  placement, break requirements, and calling the 8-ball to a pocket remain out
  of scope and are documented as such.
- Coin Flip (#27), the second mini-game — proof that adding one touches nothing
  but its own folder and one line of `main.dart`.
- A committed design-token set (colour, spacing, radius, type, motion) and a
  `ThemeData` built from it, replacing Material defaults throughout.
- Connection-lost overlay (#28) and a Bluetooth-off banner (#36) driven by the
  live adapter state.
- `MiniGameRegistry` tests and a `@visibleForTesting` reset seam (#24).
- CI coverage floor of 80% (#25) via `tool/check_coverage.dart`, and the
  real-device smoke-test runbook (#26) that covers what CI cannot.

### Changed
- **Bluetooth backend swapped** from `flutter_blue_plus` to
  `bluetooth_low_energy` (ADR-0009). The old package implements the central
  role only — it cannot advertise or run a GATT server — so the entire
  multiplayer backlog was blocked behind a dependency that structurally could
  not host a game.
- `PeerTransport` is now a message channel only; discovery moved to the lobby
  (ADR-0011). Callers can no longer set `seq` or `senderId` — the transport
  owns both.
- `BleScanner.connect` returns a live `PeerConnection` instead of a provisional
  handle.

### Removed
- `JoinController` and `JoinScreen`, superseded by `LobbyController` and the
  lobby screen, which cover the same scan → connect flow and add hosting. Their
  test coverage was carried over and extended.

### Fixed
- Hardening from a security review of the transport: outbound writes are
  serialized (concurrent sends interleaved their chunks and killed the
  session); dropped frames are counted rather than logged (the log queue was a
  remote memory-exhaustion vector); reassembly is no longer quadratic in a
  peer-chosen length; joiner writes are delivered in arrival order; advertised
  host names are scrubbed before they reach the host list.
- A client read turn state from its own rules engine, which never advances, so
  its controls never unlocked.
- The lobby closed the connection it had just handed to the game: handing off
  with `pushReplacement` disposed the lobby's controller, which disposed the
  `BleHost`, which closes the GATT link it is serving. Every hosted match would
  have died the instant it started, invisibly to a test suite where the host is
  a mock. The game is now pushed over the lobby, which stays mounted for the
  match.
- The rules engine scored pocketed balls before judging the shot, so potting
  the last ball of your group was judged as if you were already on the 8-ball.
- Removed `flutter_01.log`, committed by accident, and gitignored `*.log`.

### Previously in Unreleased

#### Added
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
- Pool rules (#22): a pure-Dart `PoolRulesEngine` for minimal 8-ball
  pass-and-play (pocket to keep shooting, scratch/miss passes the turn, 8-ball
  early = loss, 8-ball after clearing the rest = win), plus a `respawnCue` on
  the simulation so play continues after a scratch. Solids/stripes and complex
  fouls deferred to v2.
- Playable Pool (#20, #21, #23): a Flame `PoolGame` that drives the simulation
  at a fixed timestep and renders the snapshot, slingshot drag input
  (`shotFromDrag`), and a `PoolHud` turn indicator + winner/rematch card. The
  Pool tile now opens the local game instead of a "coming soon" stub.

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
