# Architecture

## Goals
- Make "many mini-games" **additive**: a new game can't break existing ones.
- Keep the Bluetooth backend swappable without touching game code.
- Treat all peer input as hostile.

## Layers
```
lib/
  core/                    interfaces + shared glue (never imports games/)
    mini_game.dart         MiniGameDescriptor — identity + entry point for a game
    mini_game_registry.dart append-only registry the shell reads
    peer_message.dart      wire model with strict inbound validation
    peer_transport.dart    PeerTransport abstraction + GameSession
    display_name.dart      scrubbing for untrusted, user-visible names
    bluetooth_service.dart app-wide "can we play right now" adapter state
    session/
      handshake.dart       name + role exchange (#13)
      session_launcher.dart connection -> transport -> handshake -> GameSession
    transport/
      peer_connection.dart  duplex ordered byte channel (radio-free)
      frame_codec.dart      length-prefixed chunking + bounded reassembly
      peer_connection_transport.dart  the concrete PeerTransport
      ble/                  the only place the radio exists
        gatt_contract.dart  service + characteristic UUIDs (ADR-0006)
        ble_scanner.dart    central (joiner) interface
        ble_host.dart       peripheral (host) interface
        bluetooth_low_energy_{scanner,host}.dart  the two hardware adapters
  games/
    <id>/                  one self-contained module per game
  shell/
    theme/                 design tokens + ThemeData
    lobby/                 host-or-join, ending in a live GameSession
    widgets/               shared shell widgets (connection overlay, BT banner)
  main.dart                registers games, renders the game list
test/
  support/                 test doubles, incl. LoopbackPeerConnection
```
Dependency rule: `games/*` may import `core/` (and `shell/theme` +
`shell/widgets`); `core/` must never import `games/*`; no game imports another
game.

## Mini-game contract
A game is one `MiniGameDescriptor` exposing `id`, `title`, multiplayer
capability, player counts, and a `build(context, {session})` returning the
playable widget. The shell lists descriptors from the registry and routes to
`build()`. It never knows what's inside a game.

Adding a game:
1. `lib/games/<id>/<id>_descriptor.dart` implementing `MiniGameDescriptor`.
2. Register it in `main.dart` (one line).
3. Build the game + logic in the same folder.

Use `/new-minigame <id>` to scaffold this. Coin Flip (`lib/games/coinflip/`) is
the worked example that proves the claim: it shares no code with Pool, and
adding it touched one line outside its own folder (#27).

## The multiplayer stack
Bottom to top, each layer knowing nothing about the one above:

| Layer | Responsibility |
|---|---|
| `BleScanner` / `BleHost` + adapters | Find a peer, or be found. The only radio code. |
| `PeerConnection` | A duplex, **ordered** byte channel to one peer, plus link-state events. No BLE types cross it. |
| `frame_codec` | Frames are length-prefixed and cut to the negotiated MTU; reassembly is bounded (ADR-0010). |
| `PeerConnectionTransport` | Validates every inbound frame and owns `seq`. Implements `PeerTransport`. |
| `SessionLauncher` + handshake | Names and roles exchanged; produces a `GameSession` (ADR-0011). |
| Game | Receives a `GameSession` whose peer is connected and named. |

**Discovery is not part of `PeerTransport`.** Scanning and advertising belong to
the lobby; a transport starts from an already-connected `PeerConnection`, so a
game cannot start a scan mid-match.

**v1 backend:** raw BLE via `bluetooth_low_energy`, which supports both the
central and peripheral roles — the host runs a GATT server, the joiner connects
to it. This enables **cross-OS play** (an iPhone and an Android can play
together). See [ADR-0002](adr/0002-multiplayer-transport-and-scope.md) for the
raw-BLE strategy, [ADR-0006](adr/0006-ble-gatt-profile.md) for the GATT profile,
and [ADR-0009](adr/0009-peripheral-capable-ble-backend.md) for why
`flutter_blue_plus` was replaced (it is central-only, so it structurally could
not host).

*The high-level, platform-locked options — Google Nearby Connections and Apple
Multipeer Connectivity — were considered and rejected: they only support
same-OS play and don't interoperate. See
[ADR-0004](adr/0004-defer-flutter-nearby-connections.md).*

## State synchronization (ADR-0003)
**Host-authoritative.** One device hosts: it owns the simulation, advances
physics/scoring, and broadcasts authoritative snapshots. The client sends inputs
and renders received state — it steps no physics at all, because two independent
forge2d worlds diverge on floating-point rounding within seconds.

For Pool: the host runs forge2d and broadcasts ball positions at 20 Hz while the
table is moving (plus every turn/winner change, which must not be dropped); the
client sends shot inputs. The host re-checks turn ownership before applying a
remote shot.

## Security model
There is no server. The boundary is the device. Inbound peer data crosses five
gates before any game sees it:

1. **Reassembly** — the peer's declared frame length is bounded *before*
   anything is allocated on it, and pending bytes cannot exceed one maximal
   frame (ADR-0010).
2. **Validation** — `PeerMessage.fromWire`; a throw means a hostile frame.
3. **Vocabulary** — unknown message types are dropped.
4. **Identity** — the first valid frame pins the peer's `senderId`; frames from
   anyone else are dropped.
5. **Replay** — `seq` must strictly increase (#29).

Beyond the frame path:
- **Names are scrubbed** wherever they come from a peer — the handshake payload
  *and* the BLE advertisement — since both reach a widget. Control and
  bidirectional-override codepoints are stripped and the result truncated
  (`core/display_name.dart`).
- **Game payloads are range-checked** by each game's codec: a ball position must
  be finite and on the table, a shot angle must be finite. A bad frame is
  dropped, never clamped into something plausible.
- **The host serves one joiner.** Withdrawing the advertisement does not stop a
  GATT server, so the service is withdrawn too and further centrals refused.
- **The link is unauthenticated by choice** — pairing prompts would defeat
  pick-up-and-play. Recorded, with what stands in its place, in the ADR-0009
  addendum.
- Minimum Bluetooth permissions per platform, with clear usage strings; no
  secrets committed; dependencies patched (Dependabot + CI).

## Testing
`LoopbackPeerConnection` (in `test/support/`) wires two `PeerConnection`s
in-process at a 20-byte chunk size — the worst case a real link presents — so the
entire stack above the radio, including two-device Pool, is tested without
hardware. The two radio adapters cannot be unit-tested and are excluded from the
CI coverage floor; [the smoke-test runbook](testing/bluetooth-smoke-test.md) is
what covers them instead.
