# 0007. A fake transport in `test/` is the no-hardware test seam

Date: 2026-06-16

## Status
Accepted

## Context
BLE is hard to test (issue #37): emulators have no Bluetooth radio, so any test
that touches a real transport needs two physical phones, two builds, and two log
streams. That is too much friction for the bulk of our logic — handshake and
role assignment (#13), message dispatch and the unknown-type drop (ADR-0005),
and every game's rules — none of which actually care *how* bytes move, only that
they arrive as validated `PeerMessage`s.

The seam that makes this testable already exists: games and shell code depend
only on the `PeerTransport` interface (advertise / discover / connect / `send` /
`incoming` / disconnect), never on a concrete backend. The security boundary,
`PeerMessage.fromWire`, is likewise already tested in isolation against hostile
input (`test/core/peer_message_test.dart`) with no transport at all.

What was missing is a recorded decision on *what consumers test against* when
there is no hardware. The #37 research surfaced the answer — a fake transport —
and rule #4 applies. The issue's own wording floated "a `FakePeerTransport` in
`lib/core/`", but production `core` must not carry test-only code, so placement
needs deciding too. The concrete implementation is reserved for #11, which the
roadmap pairs with #16 because the interface may still shift while #10
(PeerConnection) and #12 (codec) land.

## Decision
- **The no-hardware automated-test seam is a fake/loopback `PeerTransport` test
  double.** It wires two in-memory endpoints; `send()` round-trips a message
  through `toWire()` → `fromWire()` before emitting it on the peer's `incoming`
  stream, so the codec and the validation boundary run on every hop rather than
  being bypassed. This lets handshake, dispatch, and game logic run end-to-end
  with zero hardware.
- **It lives in `test/` (e.g. `test/fakes/`), not `lib/core/`.** It is a test
  artifact; keeping it out of production `core` preserves the dependency
  direction the architecture rests on. (This refines the issue's offhand
  "in lib/core/".)
- **Hostile *bytes* stay a `fromWire` concern, not a transport concern.** Because
  `send()` takes an already-typed `PeerMessage`, malformed frames cannot be
  injected through the fake. Raw-frame fuzzing belongs one layer lower, at the
  `#10` PeerConnection byte-ingestion seam, and at the `fromWire` unit tests that
  already exist.
- **Implementation is deferred to #11** (built alongside #16). This ADR fixes the
  strategy and placement, not the API.
- **Both the fake and the real `BleTransport` must pass one shared contract test
  suite** against `PeerTransport`. That suite is the anti-drift mechanism: it is
  what keeps the fake honest as the real implementation grows behavior
  (reconnect, #28).
- `mocktail` (already a dev-dependency) is the tool for interaction assertions —
  verifying a consumer calls `send()`/`disconnect()`, or scripting `incoming`.
  The loopback fake is for round-trip flow; `mocktail` is supplementary.

## Consequences
The majority of our automated coverage — game rules, scoring, handshake,
dispatch — becomes reachable without two phones, which is the difference between
a tight inner loop and one gated on hardware. `docs/testing-ble.md` records the
resulting automated-vs-manual split and the dev loop.

Trade-offs accepted: the fake must track the real interface, so it is built
*with* #16 rather than ahead of it, and the shared contract test carries the cost
of keeping the two in sync. The loopback proves **codec correctness, not BLE
reliability** — MTU negotiation, GATT fragmentation, advertising drops, and
timing are invisible to it and still require the two-device runbook (#26). The
status is Accepted because the *strategy* is settled; if the eventual
implementation needs a fundamentally different approach, that is a normal
superseding ADR, not a reason to leave this unrecorded.
