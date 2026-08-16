# 0009. Replace flutter_blue_plus with bluetooth_low_energy (peripheral role)

Date: 2026-08-16

## Status
Accepted (supersedes the backend choice in ADR-0002; the raw-BLE *strategy*
there still stands)

## Context
ADR-0002 chose raw BLE via `flutter_blue_plus`, and ADR-0006 defined a GATT
profile in which **the host runs a GATT server and advertises** a service the
joiner scans for. The joiner half (#8) shipped against `flutter_blue_plus` and
works as designed.

The host half (#7) cannot be built on it. `flutter_blue_plus` implements the
**central role only** — scan, connect, discover, read/write/subscribe. It has no
peripheral API: it cannot advertise, cannot expose a GATT service, and cannot
answer a write or push a notification. Every remaining multiplayer issue sits
behind #16 (concrete `PeerTransport`), which sits behind #9 (raw bytes), which
sits behind #7. So the backlog is blocked not on effort but on a capability the
chosen dependency does not have.

Three ways out were considered:

1. **Add a peripheral-only plugin next to `flutter_blue_plus`.** `ble_peripheral`
   covers Android/iOS/macOS/Windows but was last published 2024-12; the app
   would then run two independent BLE stacks, each with its own adapter-state
   and permission code path that must agree at runtime.
2. **`flutter_ble_peripheral`.** Recently published, but scoped to
   *advertising*; it does not give the host a writable characteristic and a
   notify channel, which is exactly what ADR-0006's profile needs.
3. **`bluetooth_low_energy` (6.2.1) for both roles.** One plugin exposing a
   symmetric `CentralManager` / `PeripheralManager` pair over
   Android/iOS/macOS/Windows/Linux, actively published, with the full
   server-side surface: `addService`, `startAdvertising`,
   `characteristicWriteRequested`, `notifyCharacteristic`, `mtuChanged`, and
   per-central connection-state events.

## Decision
Adopt **`bluetooth_low_energy` for both roles** and drop `flutter_blue_plus`.

- The host uses `PeripheralManager`: publish ADR-0006's service, advertise its
  UUID, accept writes on the input characteristic, notify on the state
  characteristic.
- The joiner uses `CentralManager`: scan filtered by the service UUID, connect,
  discover, subscribe to state, write input.
- Both radio adapters stay behind NearPlay's own interfaces (`BleScanner`,
  `BleHost`), so the swap touches the adapter files and nothing above them.
- `BluetoothLowEnergyState` maps 1:1 onto the existing `BleReadiness` vocabulary
  (`poweredOn`/`unauthorized`/`unsupported`/`poweredOff`), so the readiness gate
  and every join-failure message carry over unchanged.

Taking the symmetric single-stack option now is deliberate: exactly one thin
adapter exists today, so this is the cheapest this migration will ever be.

## Consequences
- One BLE dependency, one permission model, one adapter-state stream shared by
  both roles — instead of two stacks that must be kept in agreement.
- `flutter_blue_plus`-specific code is confined to one deleted file; the
  `JoinController` state machine and its 13 unit tests are untouched, because
  they only ever depended on `BleScanner`.
- The platform-permission declarations change shape (the new plugin documents
  its own Android/iOS requirements); the manifest/Info.plist keys are revisited
  as part of this change.
- **Unvalidated on hardware.** Both adapters are written against the package's
  real API and type-check in CI, but no device test has been run. Issue #26's
  smoke-test runbook is the gate before this is trusted; treat the adapters as
  unproven until it passes on an Android/Android and an iOS/Android pair.
- iOS peripheral advertising is more restricted than Android's (the local name
  and service UUID are what a backgrounded app may advertise). NearPlay hosts
  only while in the foreground, which stays inside those limits.
