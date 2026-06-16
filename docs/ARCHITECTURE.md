# Architecture

## Goals
- Make "many mini-games" **additive**: a new game can't break existing ones.
- Keep the Bluetooth backend swappable without touching game code.
- Treat all peer input as hostile.

## Layers
```
lib/
  core/                 interfaces + shared engine glue (depends on nothing in games/)
    mini_game.dart      MiniGameDescriptor — identity + entry point for a game
    mini_game_registry.dart  append-only registry the shell reads
    peer_transport.dart PeerTransport abstraction + GameSession
    peer_message.dart   wire model with strict inbound validation
  games/
    <id>/               one self-contained module per game
  main.dart             registers games, renders the shell
```
Dependency rule: `games/*` may import `core/`; `core/` must never import `games/*`.

## Mini-game contract
A game is one `MiniGameDescriptor` exposing `id`, `title`, multiplayer capability, player counts, and a `build()` that returns the playable widget. The shell lists descriptors from the registry and routes to `build()`. It never knows what's inside a game.

Adding a game:
1. `lib/games/<id>/<id>_descriptor.dart` implementing `MiniGameDescriptor`.
2. Register it in `main.dart` (one line).
3. Build the Flame game + logic in the same folder.
Use `/new-minigame <id>` to scaffold this.

## Local multiplayer
All multiplayer flows through `PeerTransport` (advertise, discover, connect, send, `incoming` stream, disconnect). Games receive a `GameSession` carrying the transport, the device's role (host/client), and the local player id.

**v1 backend:** raw BLE via `flutter_blue_plus` — the transport common to both platforms, enabling **cross-OS play** (an iPhone and an Android can play together). The decision and its rationale live in [ADR-0002](adr/0002-multiplayer-transport-and-scope.md); the custom GATT profile (service + characteristic UUIDs) is pinned in [ADR-0006](adr/0006-ble-gatt-profile.md). The scan/connect joiner lives in `lib/core/transport/ble/`.

*The high-level, platform-locked options — Google Nearby Connections and Apple Multipeer Connectivity — were considered and rejected: they only support same-OS play and don't interoperate. The dependency placeholder that briefly stood in for that approach was removed; see [ADR-0004](adr/0004-defer-flutter-nearby-connections.md).*

## State synchronization (ADR-0003)
**Host-authoritative.** One device hosts: it owns the simulation, advances physics/scoring, and broadcasts authoritative snapshots. The client sends inputs and renders received state. This sidesteps cross-device floating-point nondeterminism that would otherwise desync independent simulations. For Pool: host runs forge2d, sends ball transforms; client sends shot inputs.

## Security model
There is no server. The boundary is the device.
- Parse every inbound frame via `PeerMessage.fromWire`; reject malformed/oversized/replayed packets.
- Validate sequence numbers to drop replays and out-of-order frames.
- Request the **minimum** Bluetooth/location permissions per platform, with clear usage strings.
- Commit no secrets; keep dependencies patched (Dependabot + CI).
