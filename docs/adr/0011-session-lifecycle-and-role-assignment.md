# 0011. Session lifecycle, role assignment, and where discovery lives

Date: 2026-08-16

## Status
Accepted

## Context
`PeerTransport` was declared with `startAdvertising`, `startDiscovery`, and
`connect(endpointId)` alongside `send`/`incoming`. That put four different jobs
behind one interface: finding a peer, choosing one, moving bytes, and being a
game's handle on the session. It also left an awkward gap — a game handed a
`PeerTransport` could, in principle, start a scan mid-match.

By the time the transport is built, discovery has already happened: the lobby
scanned or advertised, the user picked a host, and a `PeerConnection` exists.
Meanwhile #13 (handshake), #17 (routing a `GameSession` into `game.build`), and
#6 (host/join screen) all need one answer to the same question: *who owns the
steps between "tap Pool" and "the game is running with a live peer".*

## Decision

### Discovery is not part of the transport
`PeerTransport` is a message channel and nothing else: `send`, `incoming`,
`connectionState`, `disconnect`. Finding a peer belongs to `BleScanner` /
`BleHost` and the lobby that drives them. A transport is constructed *from* an
already-connected `PeerConnection`, so a game physically cannot start a scan.

### One funnel, two entrances
Hosting and joining differ only in how a `PeerConnection` is obtained. Both
converge on the same sequence, owned by `SessionLauncher`:

```
PeerConnection ─▶ PeerConnectionTransport ─▶ handshake ─▶ GameSession ─▶ game
```

The lobby's two paths (advertise-and-wait, scan-and-pick) each produce a
connection and hand it to that one funnel, so there is a single definition of
"a session is ready" rather than one per entrance.

### Roles are assigned by the lobby, not negotiated
**Whoever advertised is the host.** That is already known locally before a byte
is exchanged, so there is nothing to negotiate and no tie to break. The
handshake still carries each side's claimed role, but only to *detect
disagreement*: two hosts or two clients means the devices disagree about the
session, and the right response is to refuse to start rather than to arbitrate.

Under ADR-0003 the host is the authority, so this also fixes who simulates.
Host is Player 1 (#13).

### The handshake carries names, and names are untrusted
Each side sends a display name; each side scrubs the one it receives. The peer's
name is attacker-controlled text on its way into a widget, so it is stripped of
control and bidirectional-override codepoints, truncated, and replaced with a
fallback when unusable — the same posture `PeerMessage.fromWire` takes toward
frames.

### Peer ids are random per session
A peer id is generated per session (`host-<8 hex>`), never derived from a device
identifier. Nothing on the wire lets a NearPlay frame be used to recognise a
device across sessions.

## Consequences
- A game receives a `GameSession` whose peer is connected and named; it never
  sees a half-open session, and it cannot reach discovery.
- The lobby owns every failure the user can act on (no host found, permission
  denied, handshake timeout), so those messages live in one place instead of
  being split between the shell and the transport.
- `GameSession` gains `remotePlayerName` / `localPlayerName`, which the HUD and
  the win screen need; a game no longer has to invent labels for the players.
- Role conflict is a hard stop rather than a recovery path. In a two-device
  lobby it can only happen if both users tapped "Host", and failing loudly is
  clearer than silently promoting one.
- Session state is in memory only. Nothing persists a name or a paired peer
  across launches; adding that means a persistence decision and its own ADR.
