# 0005. Peer message protocol vocabulary

Date: 2026-06-15

## Status
Accepted

## Context
Peers need a shared contract for the messages they exchange (issue #12). The
wire codec already exists — `PeerMessage.toWire`/`fromWire` serialize validated
JSON-over-UTF-8, and `fromWire` is the security boundary (CLAUDE.md rule #2).
What was missing is the *vocabulary*: which message types exist and what the
boundary does with an unrecognized one. Three issues build directly on this
contract — #13 (handshake + role assignment), #14 (state sync), #16 (concrete
transport) — plus #29 (replay protection). Without a recorded decision they
would each invent their own answer and diverge. This being the protocol
contract, rule #4 applies.

## Decision
- **Four transport-level message types:** `handshake`, `input`, `state`, `ping`,
  defined as the canonical `MessageType` enum. (Issue #12 named "move"; it is
  realized as `input` to match ADR-0003 and the existing code.) Game-specific
  data rides in the opaque `payload`; the type vocabulary is a fixed transport
  concern, so a new game never adds a type (it reuses `input`/`state` with its
  own payload) and therefore does not touch `core` — consistent with
  module-per-game.
- **`PeerMessage.type` stays a `String`** on the wire; `MessageType` is the
  canonical source callers build from. `fromWire` is **permissive about the type
  value** — an unrecognized but well-formed type is not a parse error.
- **Unknown-type policy:** an unrecognized type is **dropped by the dispatcher —
  it never throws at the boundary and never reaches game logic.** Dispatch
  itself lives downstream (#13/#16); #12 only records the rule.
- **Wire protocol version:** every frame carries `v` (currently `1`). `fromWire`
  rejects any other version, so peers on incompatible builds fail fast instead
  of silently mis-parsing. Bump `wireVersion` on any breaking frame-format
  change.
- **Sequencing:** `seq` is monotonic per sender; replay/reorder enforcement is
  deferred to #29.

## Consequences
The contract is fixed once, so #13/#14/#16 share one vocabulary and one
unknown-type rule instead of three. The version field is near-free now (no peers
exist yet) and avoids a wire-format retrofit plus silent desyncs once two app
versions meet. Trade-offs accepted: the vocabulary is centralized in `core`
(fine, since it is transport-level, not game-level); and because the boundary
stays permissive about the type *value*, the dispatch layer is responsible for
enforcing the drop-unknown invariant — the boundary guarantees frame *shape*,
not vocabulary membership.
