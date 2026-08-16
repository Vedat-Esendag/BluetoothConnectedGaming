import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';

/// Whether the BLE stack is usable right now.
enum BleReadiness {
  /// Supported, powered on, and permissions granted — safe to scan or host.
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
/// The scan/connect *logic* (`JoinController`) depends only on this interface
/// and is unit-tested with a mock, while the real radio calls live in a single
/// adapter validated on hardware (ADR-0009, issue #26). Implementations filter
/// scans by `GattContract.serviceUuid` and verify the contract's
/// characteristics on connect.
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

  /// Connect to [deviceId], discover the GATT contract's characteristics, and
  /// subscribe to host notifications.
  ///
  /// Returns a ready-to-use byte channel: by the time this completes, frames
  /// can flow in both directions. Throws a [BleException] (e.g.
  /// [JoinFailureReason.characteristicDiscoveryFailed]) on failure.
  Future<PeerConnection> connect(String deviceId);
}
