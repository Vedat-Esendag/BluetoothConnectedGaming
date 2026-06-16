# 0002. Multiplayer transport and scope

Date: 2026-06-12

## Status
Accepted

## Context
NearPlay is two-phone local multiplayer with no server, and we want an iPhone to
be able to play against an Android. The easy, high-level options rule that out:
Apple's Multipeer Connectivity and Google's Nearby Connections each work only
within their own platform and do not interoperate. We need one transport that
spans both operating systems, and we want game code insulated from whichever
transport we pick.

## Decision
v1 uses **raw BLE via `flutter_blue_plus`** — the transport common to iOS and
Android — to support **cross-OS play**. All game code depends on the
`PeerTransport` interface, never the concrete backend, so the transport can be
swapped without touching any game.

## Consequences
Cross-OS play is achievable from v1, which neither high-level framework could
deliver. The cost is lower-level work we now own: a custom GATT profile on both
platforms (pinned in ADR-0006) and BLE mechanics such as MTU negotiation and
frame fragmentation. Confining games to `PeerTransport` keeps that complexity in
`core` and off the game modules.
