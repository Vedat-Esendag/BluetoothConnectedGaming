# Testing & debugging BLE in NearPlay

How to develop and test the Bluetooth transport without losing your mind to
two-phone setups. This is the strategy doc that issue
[#37](https://github.com/Vedat-Esendag/BluetoothConnectedGaming/issues/37) asked
for; the test-seam decision behind it is recorded in
[ADR-0006](adr/0006-fake-transport-test-seam.md).

> **Provisional.** The fake/loopback `PeerTransport` described under *Automated
> tests* is **not implemented yet** — it is tracked by issue #11 and built
> alongside the concrete transport (#16). Today only the pieces marked
> **available now** exist. Everything else is the plan you are reading so #7–#16
> don't each reinvent it.

## The one rule that saves the most time

**A loopback/fake transport proves your *codec and logic* are right. It does not
prove *BLE* works.** MTU negotiation, GATT fragmentation, advertising drops,
reconnection, and timing are invisible to an in-memory fake and only show up on
real radios. So: push everything you can onto the no-hardware path, and spend
scarce two-phone time only on what genuinely needs it.

## What's testable where

| Layer | Needs | How |
| --- | --- | --- |
| `PeerMessage.fromWire` validation (the security boundary) | **Zero hardware** — available now | Unit tests feeding raw bytes (`test/core/peer_message_test.dart`) |
| Handshake, dispatch, game rules/scoring (`PeerTransport` consumers) | **Zero hardware** — needs the fake (#11) | Fake/loopback transport + `mocktail` |
| Connection mechanics: advertise / discover / connect / MTU / notify / disconnect | **One phone + a generic BLE tool** | nRF Connect / LightBlue standing in for the second peer at the GATT level |
| Real end-to-end `PeerMessage` exchange, reconnect, timing | **Two phones** | Two `flutter run` sessions; smoke-test runbook (#26) |

---

## Automated tests (no hardware) — the bulk of coverage

### Hostile-input testing of the boundary — *available now*

`PeerMessage.fromWire` is the security boundary (CLAUDE.md rule #2): every inbound
frame is parsed through it, and it throws `PeerMessageError` on anything
malformed, oversized (> 16 KB), wrong-version, or out-of-contract. **It needs no
transport** — you hand it raw `List<int>` bytes directly, which is exactly how a
hostile peer's frame would arrive.

This is already covered in
[`test/core/peer_message_test.dart`](../test/core/peer_message_test.dart):
non-JSON bytes, oversized frames, bad `senderId` (including path-traversal-shaped
values), negative `seq`, type-length limits, and version mismatches. Extend that
file when the contract grows; a property-based/fuzz pass over `fromWire` is a
cheap future addition since the function is pure.

### Consumer logic against a fake transport — *needs #11*

Everything above the wire — handshake/role assignment (#13), the unknown-type
drop (ADR-0005), and each game's rules — depends only on the `PeerTransport`
interface, so it can run against an in-memory **loopback transport** with no
radio. The contract that keeps the fake honest: **`send()` round-trips the
message through `toWire()` → `fromWire()` before delivering it to the peer's
`incoming` stream**, so the codec and the validation boundary execute on every
hop instead of being skipped.

Illustrative sketch (the real, tested version lands in #11 — do not copy this in
as production code):

```dart
// test/fakes/loopback_transport.dart (illustrative — imports omitted for brevity)
class LoopbackTransport implements PeerTransport {
  LoopbackTransport? _peer;
  final _in = StreamController<PeerMessage>.broadcast();

  void linkTo(LoopbackTransport p) {
    _peer = p;
    p._peer = this;
  }

  @override
  Future<void> send(PeerMessage m) async => _peer?._deliver(m.toWire());

  void _deliver(List<int> bytes) {
    try {
      _in.add(PeerMessage.fromWire(bytes)); // boundary runs every hop
    } on PeerMessageError {
      // drop hostile/garbage frame — CLAUDE.md rule #2
    }
  }

  @override
  Stream<PeerMessage> get incoming => _in.stream;

  @override
  Future<void> startAdvertising(String displayName) async {}
  @override
  Future<void> startDiscovery() async {}
  @override
  Future<void> connect(String endpointId) async {}
  @override
  Future<void> disconnect() async => _in.close();
}
```

Note the boundary this fake **cannot** test: because `send()` takes an
already-typed `PeerMessage`, you can't push a *malformed frame* through it. That
is intentional — hostile *bytes* are a `fromWire` concern (above) and, once it
exists, a concern of the raw-byte ingestion layer (#10 PeerConnection). The fake
is for *logic*, not for *frame validation*.

Per [ADR-0006](adr/0006-fake-transport-test-seam.md) the fake lives in `test/`,
and one shared **contract test** will run against both the fake and the real
`BleTransport` so they cannot silently diverge.

### `mocktail` for interaction assertions

`mocktail` (already a dev-dependency) is the right tool when you want to assert
*how* a consumer drives the transport — that it calls `send()` with the expected
message, or `disconnect()` on teardown — or to script a precise sequence on
`incoming`. Use the loopback fake for round-trip flow; reach for `mocktail` for
call-level assertions.

---

## Manual verification (needs hardware)

### One phone + a generic BLE tool

A generic BLE app — **nRF Connect** (Android/iOS) or **LightBlue**
(iOS/macOS) — can stand in for the second peer **at the GATT level**, in both
directions:

- **Our app is the host (GATT server / peripheral):** the tool acts as a
  **central** — scan, connect, discover services, subscribe to notifications, and
  write to characteristics. This is the easy, reliable direction.
- **Our app is the joiner (central):** the tool must **advertise as a peripheral**
  exposing the service UUID our app scans for. ⚠️ Tool limits matter here: nRF
  Connect's advertiser is fully featured on **Android** (custom service UUID,
  live-updating advertising data), but on **iOS** it can't set a custom service
  UUID for the advertised peripheral and won't refresh advertising data
  dynamically. So for the "advertise our service" direction prefer **nRF Connect
  on Android**, **LightBlue** (verify the exact peripheral capabilities on your
  device), or simply a second real phone.

What this buys you: debugging the connection lifecycle — advertise → discover →
connect → MTU → subscribe/notify → disconnect — and confirming our GATT service
shape. What it does **not** buy you: the tool speaks raw GATT, not our
`PeerMessage` protocol, so it cannot exercise handshake or gameplay. For that you
need two NearPlay builds.

### Two phones

Required for true end-to-end `PeerMessage` exchange, reconnection behaviour, and
the smoke-test runbook (#26). Least-painful loop:

1. **Enable wireless debugging on both devices**, so neither is tethered:
   - Android: `adb pair <host:port>` (Android 11+) then `adb tcpip 5555` /
     `adb connect <ip:port>`.
   - iOS: enable "Connect via network" for the device in Xcode once; thereafter
     `flutter` sees it over Wi-Fi. (Wireless iOS debugging is occasionally
     flaky — fall back to a cable if a session won't attach.)
2. `flutter devices` to get the two device IDs.
3. Run two sessions, one per terminal: `flutter run -d <deviceId>`.
4. Watch both sides at once: `flutter logs -d <deviceId>` per device, or
   `idevicesyslog` / Console.app for iOS. Prefix your own transport logs with the
   role (host/joiner) so two streams are readable side by side.

---

## Logging — watching both sides of a connection

Two layers, both useful:

- **The BLE stack:** `flutter_blue_plus` ships a verbose logger. Turn it up once
  at startup:

  ```dart
  // verbose stack logs: advertise/scan/connect/MTU/GATT read-write-notify
  await FlutterBluePlus.setLogLevel(LogLevel.verbose); // default is LogLevel.debug
  ```

- **Our protocol:** the stack logger knows nothing about `PeerMessage`. When the
  concrete transport lands (#16) it should carry a thin, debug-gated structured
  log over the lifecycle (advertise → discover → connect → MTU → write/notify →
  disconnect), **and log + count every frame that `fromWire` drops** — a dropped
  frame is a hostile or garbage event (rule #2), not noise to swallow silently.
  Gate it behind `kDebugMode` (or a flag) so release builds stay quiet. Prefer
  `dart:developer`'s `log` or `package:logging`. *(Recommendation for #16; not
  built yet.)*

---

## Recommended dev loop

Work outward from fastest to slowest feedback:

1. **No hardware first.** Drive new logic with unit tests against `fromWire` and
   the loopback fake. This is where most bugs are cheapest to catch.
2. **One phone + BLE tool** to validate the GATT layer — that you advertise,
   connect, negotiate MTU, and notify correctly — before involving a second
   build.
3. **Two phones last**, for real end-to-end runs and anything timing- or
   reconnection-dependent (#26).

## Tools to install

- **nRF Connect for Mobile** (Nordic Semiconductor) — Android & iOS — generic BLE
  central, and a virtual peripheral (full custom advertising on Android).
- **LightBlue** (Punch Through) — iOS/macOS — generic BLE central + peripheral
  emulator.
- **Android platform-tools** (`adb`) — wireless two-device debugging.
- **Xcode** — iOS device deployment, network debugging, Console logs.
- Already in the repo: `flutter_test` + `mocktail` (dev-dependencies) for the
  automated path.
