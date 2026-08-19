import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';

/// Why hosting failed. Mirrors [JoinFailureReason] on the joiner side so the
/// lobby can render both halves of the flow the same way.
enum HostFailureReason {
  /// No BLE hardware on this device.
  bluetoothUnsupported,

  /// The Bluetooth adapter is off.
  bluetoothOff,

  /// Bluetooth permission was denied.
  permissionDenied,

  /// The platform refused to advertise or to publish the GATT service — most
  /// often because peripheral mode is unavailable on this device.
  advertisingFailed,

  /// Anything not otherwise classified.
  unknown,
}

/// Error thrown by a [BleHost], carrying the mapped [HostFailureReason].
class BleHostException implements Exception {
  const BleHostException(this.reason, [this.detail]);

  /// The classified reason hosting failed.
  final HostFailureReason reason;

  /// Optional platform detail, for logging only (never shown to users).
  final String? detail;

  @override
  String toString() =>
      'BleHostException(${reason.name}${detail == null ? '' : ': $detail'})';
}

/// The BLE peripheral operations the host (#7) needs.
///
/// The counterpart to [BleScanner]: this side publishes ADR-0006's GATT
/// service, advertises its UUID, and waits for a joiner. Like the scanner it is
/// an interface so the lobby logic can be unit-tested against a fake while the
/// radio calls stay in one adapter (ADR-0009).
abstract class BleHost {
  /// Check support, adapter power, and permissions — requesting permission if
  /// needed. Callers must not advertise unless this returns
  /// [BleReadiness.ready].
  Future<BleReadiness> ensureReady();

  /// Publish the NearPlay GATT service and start advertising under
  /// [displayName], which is what joiners see in their host list.
  ///
  /// Throws a [BleHostException] if the platform refuses.
  Future<void> startAdvertising(String displayName);

  /// Joiners that have connected *and* subscribed to the state characteristic,
  /// i.e. are ready to exchange frames.
  ///
  /// Emits at most one connection per joiner. NearPlay is a two-device game, so
  /// the lobby takes the first and stops advertising.
  ///
  /// **The host keeps serving an emitted connection until it is closed.** Its
  /// GATT service must stay published and its platform subscriptions alive for
  /// as long as the match lasts, so whoever holds a `BleHost` must outlive the
  /// session it produced — [dispose] closes the connection along with
  /// everything else.
  Stream<PeerConnection> get connections;

  /// Stop advertising. Existing connections stay up, and the GATT service
  /// stays published — see [stopAccepting].
  Future<void> stopAdvertising();

  /// Stop advertising *and* stop serving new joiners.
  ///
  /// Called once a joiner has been accepted. Stopping the advertisement alone
  /// is not enough: a central that saw an earlier advertisement still knows
  /// this device's address and can connect to a published GATT service, so
  /// closing the session to newcomers means withdrawing the service too.
  Future<void> stopAccepting();

  /// Stop advertising, drop any connected joiner, and release resources.
  Future<void> dispose();
}
