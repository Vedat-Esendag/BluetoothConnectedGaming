# 0002. Multiplayer transport and scope

Date: 2026-06-12

## Status
Accepted

## Context
The easy local-multiplayer frameworks are platform-locked: Apple's Multipeer
Connectivity and Google's Nearby Connections do not interoperate. True
iPhone-to-Android play over Bluetooth requires raw BLE with a custom protocol on
both platforms — a meaningful chunk of work we don't want blocking v1.

## Decision
v1 uses **flutter_nearby_connections** (Nearby on Android, Multipeer on iOS),
supporting **same-OS play only** (two Androids, or two iPhones). All game code
depends on the `PeerTransport` interface, never the concrete backend.

Cross-OS play (iPhone ⇄ Android) is a **dedicated later milestone**, implemented
behind the same `PeerTransport` interface using raw BLE (`flutter_blue_plus`) and
a custom GATT message protocol.

## Consequences
v1 ships quickly with a clean same-OS experience. Because games only see
`PeerTransport`, adding the BLE backend later touches transport code, not games.
Trade-off: no cross-OS play until the BLE milestone lands; this is communicated
in the UI ("connect with the same kind of phone").
