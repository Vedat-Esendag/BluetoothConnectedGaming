# 0004. Defer the flutter_nearby_connections dependency

Date: 2026-06-13

## Status
Accepted (defers part of ADR-0002; does not supersede it)

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
CI builds a clean app and stays green. When `PeerTransport` gets a concrete
implementation, the backend is re-added at that point — on a version or fork
that declares an Android namespace and builds under AGP 8, and exercised on real
devices then. If no compatible release materialises, the raw-BLE path
(`flutter_blue_plus`, ADR-0002's later milestone) becomes the v1 backend
instead. Until then, the documented v1 transport is a plan, not a wired-up
dependency, and the doc comment in `peer_transport.dart` describes intent rather
than a present package.
