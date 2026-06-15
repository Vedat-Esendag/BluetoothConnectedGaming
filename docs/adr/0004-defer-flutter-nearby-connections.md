# 0004. Defer the flutter_nearby_connections dependency

Date: 2026-06-13

## Status
Superseded (2026-06-15) — resolved by the pivot to raw BLE (ADR-0002, ADR-0006).

## Context
ADR-0002 selects `flutter_nearby_connections` as the v1 local-multiplayer
backend (Nearby Connections on Android, Multipeer Connectivity on iOS). The
package was added to `pubspec.yaml` during scaffolding, but nothing uses it yet:
`PeerTransport` is an abstract interface with no concrete implementation, and no
Dart code imports the package.

`flutter_nearby_connections` 1.1.2 (its latest release) targets Android Gradle
Plugin 3.5 / Kotlin 1.7 and does not build under this project's toolchain
(AGP 8.11.1 / Kotlin 2.2.20 / JDK 17). Forcing it to build required stacking
Gradle workarounds — injecting an Android namespace for the plugin, then
reconciling Java/Kotlin JVM targets — with the manifest `package` attribute the
likely next failure. This broke the Android CI build for a dependency that isn't
even referenced.

## Decision
Remove `flutter_nearby_connections` from `pubspec.yaml` for now. ADR-0002's
choice of the same-OS Nearby/Multipeer backend for v1 still stands; we simply do
not carry the dependency until the transport is actually implemented.

## Consequences
Removing the dependency kept CI green at the time. The conditional this ADR set
up — re-add `flutter_nearby_connections` if a compatible release appeared,
otherwise fall back to raw BLE — has resolved in favour of **raw BLE**: no
compatible release was adopted and the package was never re-added. NearPlay has
committed to `flutter_blue_plus` (ADR-0002); its GATT profile is pinned in
ADR-0006 and the scan/connect joiner ships in `lib/core/transport/ble/`.
`flutter_nearby_connections` is therefore abandoned, not merely deferred. This
ADR is retained as the record of why the dependency was removed.
