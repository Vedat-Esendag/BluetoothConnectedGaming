/// Whether the BLE stack is usable right now.
enum BleReadiness {
  /// Supported, powered on, and permissions granted — safe to scan.
  ready,

  /// The device has no BLE hardware. Dead end; no recovery.
  unsupported,

  /// BLE is supported but the adapter is turned off. Recoverable.
  poweredOff,

  /// The OS denied (or the user declined) Bluetooth permission. Recoverable
  /// via Settings.
  unauthorized,
}

/// A host discovered during a scan, advertising the NearPlay service.
class DiscoveredHost {
  const DiscoveredHost({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// Stable per-device identifier (the platform remote id).
  final String id;

  /// Advertised device name; may be empty (the UI falls back to [id]).
  final String name;

  /// Signal strength in dBm (higher is closer); useful for ordering.
  final int rssi;
}

/// A live connection to a host whose GATT characteristics have been discovered.
///
/// Deliberately minimal and **provisional** for #8: it proves a connection was
/// established and the contract's characteristics exist, and allows teardown.
/// The full read / write / notify surface (plus the negotiated MTU) is added by
/// #10 when it wraps this into a `PeerConnection` — see ADR-0006. Do not build
/// on this shape yet.
abstract class BleConnection {
  /// The connected device's identifier.
  String get deviceId;

  /// UUIDs of the characteristics discovered on the host's service.
  List<String> get characteristicUuids;

  /// Tear down the connection.
  Future<void> disconnect();
}

/// Why a join attempt failed. Each value maps to a specific user-facing message
/// and recovery action in the join UI.
enum JoinFailureReason {
  /// No BLE hardware on this device.
  bluetoothUnsupported,

  /// The Bluetooth adapter is off.
  bluetoothOff,

  /// Bluetooth permission was denied.
  permissionDenied,

  /// The scan completed without finding any NearPlay host.
  noHostFound,

  /// A host was found but the connection attempt was refused or dropped.
  connectionRefused,

  /// Connected, but the host did not expose the expected GATT characteristics.
  characteristicDiscoveryFailed,

  /// Anything not otherwise classified.
  unknown,
}

/// Error thrown by a [BleScanner], carrying the mapped [JoinFailureReason] so
/// the controller can translate it straight into a [JoinFailureReason] state.
class BleException implements Exception {
  const BleException(this.reason, [this.detail]);

  /// The classified reason this operation failed.
  final JoinFailureReason reason;

  /// Optional platform detail, for logging only (never shown to users).
  final String? detail;

  @override
  String toString() =>
      'BleException(${reason.name}${detail == null ? '' : ': $detail'})';
}

/// The BLE central operations the joiner (#8) needs.
///
/// Mirrors why `PeerTransport` is abstract: the scan/connect *logic*
/// (`JoinController`) depends only on this interface and is unit-tested with a
/// mock, while the real `flutter_blue_plus` calls live in a single adapter that
/// is validated on hardware (ADR-0006, issue #26). Implementations filter scans
/// by `GattContract.serviceUuid` and verify the contract's characteristics on
/// connect.
abstract class BleScanner {
  /// Check support, adapter power, and permissions — requesting permission if
  /// needed — and report the current [BleReadiness]. Callers must not scan
  /// unless this returns [BleReadiness.ready].
  Future<BleReadiness> ensureReady();

  /// Scan for hosts advertising the NearPlay service. The returned stream emits
  /// each discovered host and closes when the scan stops or [timeout] elapses;
  /// it delivers a [BleException] on its error channel if scanning fails.
  Stream<DiscoveredHost> scan({required Duration timeout});

  /// Stop an in-progress scan.
  Future<void> stopScan();

  /// Connect to [deviceId], discover its services, and confirm the GATT
  /// contract's characteristics are present. Throws a [BleException] (e.g.
  /// [JoinFailureReason.characteristicDiscoveryFailed]) on failure.
  Future<BleConnection> connect(String deviceId);
}
