# 0010. Frame chunking, reassembly, and replay protection

Date: 2026-08-16

## Status
Accepted

## Context
ADR-0005 defines a `PeerMessage` as a JSON frame of up to 16 KiB. ADR-0006 sends
those frames over two GATT characteristics and explicitly defers the size
problem to #9: **a BLE write or notification is bounded by the negotiated MTU**
— 20 usable bytes by default, ~180 after a typical Android negotiation, ~512 at
best. A Pool `state` snapshot of 16 balls does not fit in one packet, so the
byte layer has to split frames and put them back together.

Reassembly on the receiving side is a security boundary as much as a transport
detail. Golden rule #2 says nothing from the peer is trusted, and a reassembler
is the classic place to get that wrong: a hostile peer that sends a huge length
header, or an endless stream of chunks that never completes a frame, makes the
receiver allocate without bound.

Separately, #29 records that `PeerMessage.seq` exists and is documented as
replay protection, but nothing enforces it. `fromWire` validates `seq >= 0` and
stops there — a peer can resend a captured frame verbatim and the game will act
on it twice. That enforcement has to land with the transport, not after it.

## Decision

### Chunking
A frame is sent as a **4-byte big-endian unsigned length header followed by the
payload bytes**, and that byte stream is cut into MTU-sized chunks by the
sender. The receiver appends chunks to a buffer and emits a frame as soon as the
buffer holds a complete one; a chunk may carry the tail of one frame and the
head of the next.

This works because both directions are **ordered and reliable**: GATT writes
*with response* and notifications on a single connection are delivered in order
by the link layer. NearPlay never has to reorder or retransmit — the moment that
stops being true (multi-connection, or writes without response), this decision
has to be revisited.

Rejected: a per-chunk sequence/total header (e.g. `[frameId, i, n]`). It costs
bytes on every chunk to solve reordering that an ordered stream does not have.

### Reassembly limits (the security half)
- The declared length is rejected outright if it exceeds
  `PeerMessage.maxFrameBytes`. The receiver never allocates on a peer's say-so.
- A frame whose bytes do not arrive is bounded by that same cap, so a peer that
  streams chunks forever cannot grow the buffer past 16 KiB.
- A protocol violation (an over-long declared length) **resets the reassembler
  and reports a stream error**. It is not recoverable by skipping bytes: once
  the framing is wrong, every subsequent byte boundary is suspect, so the
  session is treated as compromised rather than resynchronised.
- A frame that reassembles cleanly but fails `PeerMessage.fromWire` is dropped
  *without* dropping the stream — that is one bad message, not a broken framing.

### Replay protection
The concrete transport keeps a **`lastSeq` per sender** and drops any frame
whose `seq` is less than or equal to the last accepted one, before it reaches
game code. Outbound frames carry a strictly increasing counter owned by the
transport, so callers cannot forget to set it.

The transport also **pins the peer's identity**: the first inbound frame fixes
the peer's `senderId`, and frames claiming a different id are dropped. In a
two-device session there is exactly one legitimate remote sender, so a change of
id means a spoofed or crossed frame.

## Consequences
- The byte layer above BLE is a plain ordered stream, so the loopback test
  double (#11) is genuinely equivalent to the radio: the same chunking and the
  same reassembly run in tests, and game logic can be developed without hardware.
- Replay, reordering, and identity-spoofing are handled in one place that every
  game inherits, rather than each game re-checking `seq`.
- The 4-byte header is generous for a 16 KiB cap (2 would do). It is kept for
  alignment with the documented limit and because the cost is per frame, not per
  chunk.
- Chunk size follows the negotiated MTU, so throughput improves automatically on
  links that negotiate up, with no protocol change.
- A dropped or corrupted chunk desynchronises the stream permanently. BLE's
  link-layer reliability is what rules this out; it is an assumption, and the
  smoke-test runbook (#26) is where it gets checked against real radios.

## Addendum (2026-08-16): limits a security audit surfaced

Recorded so they are known trade-offs rather than oversights.

- **Replay protection is scoped to one connection.** `lastSeq` and the pinned
  peer id live for the lifetime of one transport, and a transport is built per
  `PeerConnection`. A peer that drops and reconnects therefore starts from
  `seq = -1` with no pinned identity, so frames captured from an *earlier*
  session can be replayed into a new one. What this buys an attacker is
  limited: they cannot forge new frames, and the worst case is winning the race
  to pin an identity and so denying the genuine peer — a nuisance, not a
  takeover. Closing it properly means a per-session nonce echoed on every frame,
  which costs bytes on every packet. Deferred deliberately; a reconnect is
  treated as a **new game**, never a resumed one, which is what keeps the
  window this narrow.
- **Framing assumes an honest writer.** ADR-0010's ordering guarantee comes
  from GATT writes *with response*. Nothing stops a hostile central issuing
  write *commands* instead, so ordering is a peer-cooperation assumption. A
  peer that violates it corrupts its own stream and gets the session torn down,
  which is the intended outcome.
- **Rejected frames are counted, not logged.** A log line per dropped frame is
  itself a remote memory-exhaustion vector: Flutter's `debugPrint` queues into
  an unbounded buffer that drains at roughly a kilobyte per second, so a peer
  streaming garbage could grow that queue far faster than it empties.
  `droppedFrameCount` is the diagnostic; milestones are logged in debug builds
  only.
