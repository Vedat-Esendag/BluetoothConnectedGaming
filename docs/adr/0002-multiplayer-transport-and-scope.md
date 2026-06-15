# 0002. Multiplayer transport and scope

Date: 2026-06-12

## Status
Accepted

## Context
The easy local-multiplayer frameworks are platform-locked: Apple's Multipeer
Connectivity and Google's Nearby Connections do not interoperate.

## Decision
v1 uses **flutter_blue_plus** used supporting  **cross-OS play**. All game code
depends on the `PeerTransport` interface, never the concrete backend.
