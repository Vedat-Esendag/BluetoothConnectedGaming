# 0008. Pool simulation layering and contract

Date: 2026-06-17

## Status
Accepted

## Context
Pool is built locally (single-device, pass-and-play) before the Bluetooth
transport exists, so work can proceed in parallel with the transport track.
[ADR-0003](0003-state-synchronization.md) already requires the host to run a
**deterministic** simulation it can broadcast. If the local build entangles
physics with rendering, input, or the session, wiring in multiplayer later
becomes a rewrite rather than a wire-up. We need the boundaries fixed up front.

A spike (`test/games/pool/forge2d_headless_spike_test.dart`) confirmed `forge2d`
can be stepped in a pure-Dart test with no `package:flame` import, and that
stepping is deterministic — so a headless simulation core is viable.

## Decision
Pool is structured as four layers under `lib/games/pool/`, and the only
difference between local and multiplayer play is *where the snapshot comes from*:

```
INPUT   ShotCommand  ──▶  SIM  PoolSimulation.step(commands) ──▶  STATE PoolSnapshot ──▶ RENDER (Flame)
```

1. **Headless physics.** `PoolSimulation` depends on the `forge2d` package
   **directly** and must not import `package:flame/...`. flame_forge2d is used
   only in the render layer.
2. **Role-agnostic simulation.** `PoolSimulation` never receives `GameSession`
   and never knows whether it is host or client. The *caller* drives it: the
   host advances physics from inputs; a future client applies received
   snapshots. No session/transport concern leaks into the sim or rules engine.
3. **Plain-Dart DTOs.** `ShotCommand` and `PoolSnapshot` use only `double`/
   `int`/`String`/`bool` (no `Vector2`/forge2d types), so they are trivially
   serializable into a `PeerMessage` payload later. The wire mapping itself is
   deferred to a Pool-owned `pool_wire.dart` when the transport lands — it is
   not written now.
4. **Fixed timestep.** The simulation steps at a fixed `dt`; rendering reads the
   latest snapshot. This is what makes the determinism test stable.

## Consequences
The determinism test ADR-0003 mandates is achievable in pure Dart with no widget
pump. Rendering, rules, and (later) transport all consume the same `PoolSnapshot`,
so multiplayer is additive. The import boundary is analyzer-enforceable (the sim
must not reference Flame). Trade-off: a little upfront discipline (DTOs instead of
reading `Body` directly) in exchange for never rewriting the core; and Pool now
depends on `forge2d` directly in addition to flame_forge2d.
