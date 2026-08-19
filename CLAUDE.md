# NearPlay — Working Agreement

Read this at the start of every session. It is the source of truth; chat history is not.

## What we're building
A Flutter app hosting many small mini-games played **locally over Bluetooth, two phones, no server**. First game: Pool, with real physics.

## Golden rules (non-negotiable)
1. **Module per game.** Each mini-game lives in `lib/games/<id>/` and exposes one `MiniGameDescriptor`. The shell finds games through `MiniGameRegistry` only — never import another game's internals. Adding a game must not touch existing games.
2. **Never trust the peer.** Every inbound packet is parsed through `PeerMessage.fromWire`, which validates and throws on anything malformed. A throw means a hostile/garbage frame — drop it. There is no server to sanitize input; this validation *is* the security boundary.
3. **Deterministic state via a host.** For multiplayer, one device is the **host**: it runs the simulation (physics, scoring) and broadcasts authoritative state; the client sends inputs and renders what it's told. Do not run independent physics on both devices — floating-point divergence will desync them. The host also re-checks whose turn it is before applying a remote input; a client asking at an illegal moment is ignored, not trusted. (See ADR-0003.)
4. **Decisions get an ADR.** Any architectural choice (new dependency, transport change, sync model, persistence) is recorded in `docs/adr/` before/with the code. Use `/adr <title>`.
5. **No secrets in the repo.** No keys, tokens, or signing material committed. There's little to leak in a serverless app — keep it that way.
6. **Small, focused commits.** Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`). One logical change per commit.

## Architecture
See `docs/ARCHITECTURE.md`. Layers: `lib/core/` (interfaces + engine glue), `lib/games/<id>/` (modules), transport behind `PeerTransport`. Games depend on `core`; `core` depends on nothing in `games`.

## Tech stack
Flutter (stable) · Flame (game loop/rendering) · flame_forge2d (2D physics) · bluetooth_low_energy (raw BLE, **both** central and peripheral roles — the host runs a GATT server; see ADR-0009) · very_good_analysis (lints) · mocktail (test doubles).

Games: `pool` (forge2d, host-authoritative) and `coinflip` (the additive-architecture proof, #27).

## Commands
- Run: `flutter run`
- Test: `flutter test` (with coverage: `flutter test --coverage`)
- Coverage floor: `dart run tool/check_coverage.dart` (CI fails below 80%)
- Analyze: `flutter analyze`
- Format: `dart format .`

## The loop
1. **Decide** — at a fork, convene the council (debate, then an ADR). Don't guess on architecture.
2. **Build** — implement the smallest slice that works.
3. **Review** — hand the diff to the subagents: `security-reviewer`, `code-reviewer`, `maintenance`. Use `/review`.
4. **Gate** — hooks auto-format on edit and block on `flutter analyze` failure; CI runs analyze + full tests on every PR.
5. **Ship** — conventional commit, PR, merge when CI is green.

Use subagents deliberately, not constantly. Reach for `security-reviewer` whenever transport, permissions, or inbound-data handling changes; `code-reviewer` after any non-trivial change; `maintenance` when duplication or coverage gaps appear.

## Code style
- Follow `very_good_analysis`. Keep `flutter analyze` clean — warnings are failures.
- Prefer small, named functions and explicit types on public APIs.
- No dead code, no commented-out blocks left behind.

## Testing
- Every mini-game ships with tests for its rules/scoring.
- `PeerMessage` validation is tested against hostile input (see `test/core/peer_message_test.dart`), as is the framing layer and every inbound transport gate.
- The host simulation must have a determinism test: same inputs → same state.
- **No hardware needed.** `LoopbackPeerConnection` (`test/support/`) wires two peers in-process at a 20-byte chunk size — the worst case a real BLE link presents — so the whole stack above the radio, including two-device Pool, is testable in CI.
- **The two radio adapters cannot be.** They are excluded from the coverage floor; `docs/testing/bluetooth-smoke-test.md` is what covers them, and it must be run before merging anything under `lib/core/transport/ble/`.

## Definition of done
Code formatted, `flutter analyze` clean, tests written and passing, coverage floor met, docs/CHANGELOG updated, ADR added if the change was architectural, reviewed by the relevant subagent(s). Transport changes additionally need the real-device smoke test.

## Where things are
`docs/ARCHITECTURE.md` has the full layer map. The short version:
- The multiplayer stack is `BleScanner`/`BleHost` → `PeerConnection` (bytes) → `frame_codec` (chunking) → `PeerConnectionTransport` (validation) → handshake → `GameSession` → game. Each layer knows nothing about the one above.
- **Discovery is not on `PeerTransport`.** Scanning and advertising belong to the lobby; a transport starts from an already-connected peer, so a game cannot start a scan mid-match (ADR-0011).
- Untrusted text (a peer's name, a BLE advertised name) goes through `core/display_name.dart` before it reaches a widget.
