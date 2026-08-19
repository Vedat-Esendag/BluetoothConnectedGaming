# NearPlay — Development Roadmap

Live tracker: https://github.com/Vedat-Esendag/BluetoothConnectedGaming/issues

---

## Where we are

**M1 (transport) and M2 (Pool) are done.** The critical path that this document
used to chart — from "undecided transport" to "Pool is playable" — has been
walked end to end: two devices discover each other over BLE, hand-shake into a
session, and play a real game of 8-ball with the host simulating and the client
rendering.

The one caveat that outranks everything else below:

> **The BLE adapters have never run on a radio.** They type-check and the whole
> stack above them is tested over a loopback link, but no code here has actually
> advertised or scanned on hardware. `docs/testing/bluetooth-smoke-test.md` is
> the gate, and it needs two phones — ideally one Android and one iOS.

### The critical path, as walked

```
#15 (ADR) → #12 (codec) → #7+#8 (host + joiner) → #9 (bytes) → #10 (PeerConnection)
  → #29+#16 (replay + transport) → #13 (handshake) → #17 (session wiring)
  → #19 (simulation) → #20+#21 (input + rendering) → #22 (rules) → #23 (win screen)
```

Two things the original plan did not anticipate:

- **#7 was blocked by the dependency, not by effort.** `flutter_blue_plus` is
  central-role only — it cannot advertise or run a GATT server — so the host
  half was impossible until the backend was swapped (ADR-0009). Everything
  downstream was waiting on a package that structurally could not do the job.
- **Framing had to be invented.** ADR-0006 deferred the MTU problem to #9; it
  turned out to need its own chunking protocol and a bounded reassembler, which
  is ADR-0010.

---

## What is left

### Needs hardware
- **#26 smoke test** — the runbook exists and is written; it has not been *run*.
  Nothing else in this list should be trusted until it passes.

### Pool, beyond the MVP rules
The rules engine covers group assignment, first-contact fouls, the rail
requirement, and the win condition. Deliberately still simplified:
- **Ball-in-hand placement.** A foul sets the `ballInHand` flag, but the cue
  ball respawns at the head spot instead of being placed by the incoming
  player. This is a UI feature (drag the cue ball to a legal spot), not a
  missing rule.
- **The break** is treated as an ordinary shot — no "four balls to a cushion"
  requirement, no re-rack.
- **Calling the 8-ball** to a pocket is not required.

### Session robustness
- **Reconnect.** A dropped link currently ends the game. Resuming would need a
  session identity that survives the connection, because replay protection is
  scoped to one transport (ADR-0010 addendum) — so this is a protocol change,
  not a UI one.
- **Persistence.** Names and paired peers are in-memory only; adding storage is
  a dependency decision and needs its own ADR.

### Nice to have
- A third mini-game. The registry contract is proven by Coin Flip (#27), so
  this is now genuinely additive.
- Delta compression for `state` frames, if the smoke test shows the 20 Hz full
  snapshot is too heavy on a real link. Measure before optimising.

---

## Architecture reference

See [ARCHITECTURE.md](ARCHITECTURE.md) for the layer map, and `docs/adr/` for
the decisions. The load-bearing ones:

| ADR | Decision |
|---|---|
| 0002 | Raw BLE, for cross-OS play |
| 0003 | Host-authoritative state |
| 0006 | The GATT profile both roles share |
| 0009 | `bluetooth_low_energy` for both central and peripheral |
| 0010 | Frame chunking, bounded reassembly, replay protection |
| 0011 | Session lifecycle; discovery lives in the lobby, not the transport |
