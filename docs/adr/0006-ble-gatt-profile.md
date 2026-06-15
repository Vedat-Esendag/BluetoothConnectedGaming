# 0006. BLE GATT profile for the host/joiner transport

Date: 2026-06-15

## Status
Accepted

## Context
ADR-0002 commits NearPlay's transport to raw BLE via `flutter_blue_plus`. The
host (#7) runs a GATT server and advertises a service; the joiner (#8) scans for
that service, connects, and discovers its characteristics. For the two halves to
interoperate they must share one contract: the service UUID, the characteristic
UUIDs, and each characteristic's direction/role. If #7 and #8 each invent their
own UUIDs they will never connect — and the failure is silent (an empty scan).
ADR-0005 fixed the *message* vocabulary; this fixes the *GATT* profile those
messages travel over. Rule #4 applies (transport/protocol decision).

## Decision
- **One service, two characteristics**, defined once in
  `lib/core/transport/ble/gatt_contract.dart` — that file is the **canonical
  source**; the UUIDs below are reproduced for the decision record only.
  - **Service** `e6695a2e-ec70-42b7-b660-84c1a06435df` — the NearPlay session
    service the host advertises and the joiner filters on.
  - **State characteristic** `0beeb145-5630-4c16-aa74-e62518406b28` —
    host → joiner, **notify**. Carries authoritative `state` frames
    (ADR-0003 host-authoritative model; `MessageType.state`).
  - **Input characteristic** `9cca3888-905a-4a67-bc4b-b1e19af17f8c` —
    joiner → host, **write**. Carries `input` frames (`MessageType.input`).
  - `handshake`/`ping` (ADR-0005) ride these same two characteristics in the
    direction their flow dictates; there is no extra characteristic per message
    type, mirroring how adding a game adds no message type.
- **The host advertises the service UUID in its advertisement packet** (not only
  in the GATT table). `flutter_blue_plus`'s `startScan(withServices: [...])`
  filters on *advertised* services, and `withServices` is *required on iOS* for
  privacy. Advertising the UUID is therefore part of this contract, owned by #7.
- UUIDs are randomly generated 128-bit v4 values (not 16-bit SIG-assigned),
  appropriate for a vendor-specific profile.

## Consequences
#7 and #8 share one source of truth, so they connect or fail loudly — a contract
change is a one-line diff both consume rather than two implementations drifting
apart. Centralizing the profile in `core` keeps it transport-level and out of
games.

Deferred / inherited by later issues (recorded here so they are not
rediscovered):
- **MTU.** BLE characteristic writes are bounded by the negotiated MTU
  (~20 bytes by default, up to ~512). A `PeerMessage` frame (≤16 KiB) will not
  fit a single write, so #9 (raw bytes) owns fragmentation/reassembly and
  #10/#16 expose the negotiated MTU. #8 stops at connection + discovery and
  moves no frames.
- **`BleConnection` surface.** #8 ships a deliberately minimal, provisional
  connection handle (discovered characteristics + `disconnect`). The intended
  full surface for #10 to wrap is read / write / notification-subscribe per
  characteristic plus an MTU getter; it stays `@experimental` until #10 consumes
  it.
