import 'dart:async';

import 'package:bluetooth_connected_gaming/core/display_name.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_readiness_mapping.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/gatt_contract.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart' as ble;
import 'package:flutter/foundation.dart';

/// `bluetooth_low_energy`-backed [BleScanner] — the joiner half of the radio
/// layer (ADR-0009), and one of only two files in the app that import the BLE
/// package.
///
/// **Not unit-tested**: it talks to hardware. The scan/connect *logic* it
/// serves lives in `LobbyController`, which is fully tested against a mock; what
/// is left here is platform-call sequencing, validated on real devices per the
/// #26 smoke-test runbook.
class BluetoothLowEnergyScanner implements BleScanner {
  BluetoothLowEnergyScanner({ble.CentralManager? manager})
    : _manager = manager ?? ble.CentralManager();

  final ble.CentralManager _manager;

  final ble.UUID _serviceUuid = ble.UUID.fromString(GattContract.serviceUuid);
  final ble.UUID _stateUuid = ble.UUID.fromString(
    GattContract.stateCharacteristicUuid,
  );
  final ble.UUID _inputUuid = ble.UUID.fromString(
    GattContract.inputCharacteristicUuid,
  );

  @override
  Future<BleReadiness> ensureReady() async {
    if (_manager.state == ble.BluetoothLowEnergyState.unsupported) {
      return BleReadiness.unsupported;
    }
    if (_manager.state == ble.BluetoothLowEnergyState.unauthorized) {
      // Android requires an explicit runtime request; on iOS this is a no-op
      // once the usage description has been shown.
      await _manager.authorize();
    }
    return readinessFrom(_manager.state);
  }

  @override
  Stream<DiscoveredHost> scan({required Duration timeout}) {
    final controller = StreamController<DiscoveredHost>();
    final seen = <String>{};
    StreamSubscription<ble.DiscoveredEventArgs>? discoveredSub;
    Timer? deadline;

    Future<void> stop() async {
      deadline?.cancel();
      await discoveredSub?.cancel();
      discoveredSub = null;
      await stopScan();
    }

    controller.onCancel = stop;

    Future<void> start() async {
      // Subscribe before starting so no early advertisement is missed.
      discoveredSub = _manager.discovered.listen(
        (event) {
          final id = event.peripheral.uuid.toString();
          if (!seen.add(id)) return;
          if (controller.isClosed) return;
          controller.add(
            DiscoveredHost(
              id: id,
              // An advertised name comes from an unauthenticated device that
              // has not connected yet — it never reaches a widget unscrubbed.
              name: sanitizeDisplayName(
                event.advertisement.name,
                fallback: '',
              ),
              rssi: event.rssi,
            ),
          );
        },
        onError: (Object error, StackTrace _) {
          if (!controller.isClosed) controller.addError(_mapScanError(error));
        },
      );

      try {
        await _manager.startDiscovery(serviceUUIDs: <ble.UUID>[_serviceUuid]);
      } on Object catch (error) {
        if (!controller.isClosed) {
          controller.addError(_mapScanError(error));
          await controller.close();
        }
        return;
      }

      // The package scans until told to stop, so the timeout is ours to keep.
      deadline = Timer(timeout, () async {
        await stop();
        if (!controller.isClosed) await controller.close();
      });
    }

    unawaited(start());
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    try {
      await _manager.stopDiscovery();
    } on Object catch (error) {
      // Stopping a scan that is not running is not worth surfacing.
      debugPrint('BluetoothLowEnergyScanner: stopDiscovery failed — $error');
    }
  }

  @override
  Future<PeerConnection> connect(String deviceId) async {
    final ble.Peripheral peripheral;
    try {
      peripheral = await _manager.getPeripheral(deviceId);
      await _manager.connect(peripheral);
    } on Object catch (error) {
      throw BleException(JoinFailureReason.connectionRefused, '$error');
    }

    try {
      final services = await _manager.discoverGATT(peripheral);
      final service = services.where((s) => s.uuid == _serviceUuid).firstOrNull;
      final stateCharacteristic = service?.characteristics
          .where((c) => c.uuid == _stateUuid)
          .firstOrNull;
      final inputCharacteristic = service?.characteristics
          .where((c) => c.uuid == _inputUuid)
          .firstOrNull;

      if (stateCharacteristic == null || inputCharacteristic == null) {
        throw const BleException(
          JoinFailureReason.characteristicDiscoveryFailed,
        );
      }

      // Subscribe before returning, so the caller's connection is live the
      // moment it is handed over and no early host frame is lost.
      await _manager.setCharacteristicNotifyState(
        peripheral,
        stateCharacteristic,
        state: true,
      );

      return _CentralPeerConnection(
        manager: _manager,
        peripheral: peripheral,
        stateCharacteristic: stateCharacteristic,
        inputCharacteristic: inputCharacteristic,
      );
    } on BleException {
      await _disconnectQuietly(peripheral);
      rethrow;
    } on Object catch (error) {
      // A GATT error after connect must not leave the device connected.
      await _disconnectQuietly(peripheral);
      throw BleException(
        JoinFailureReason.characteristicDiscoveryFailed,
        '$error',
      );
    }
  }

  Future<void> _disconnectQuietly(ble.Peripheral peripheral) async {
    try {
      await _manager.disconnect(peripheral);
    } on Object catch (error) {
      debugPrint('BluetoothLowEnergyScanner: disconnect failed — $error');
    }
  }

  Object _mapScanError(Object error) {
    // Best-effort: on Android a denied scan permission surfaces here. Refine
    // the classification against real devices (#26).
    final text = '$error'.toLowerCase();
    if (text.contains('permission') || text.contains('unauthorized')) {
      return const BleException(JoinFailureReason.permissionDenied);
    }
    return BleException(JoinFailureReason.unknown, '$error');
  }
}

/// The joiner's side of the byte channel: writes go to the host's input
/// characteristic, inbound bytes arrive as notifications on the state
/// characteristic (ADR-0006).
class _CentralPeerConnection implements PeerConnection {
  _CentralPeerConnection({
    required ble.CentralManager manager,
    required ble.Peripheral peripheral,
    required this.stateCharacteristic,
    required this.inputCharacteristic,
  }) : _manager = manager,
       _peripheral = peripheral {
    _notifiedSub = _manager.characteristicNotified.listen((event) {
      if (event.peripheral.uuid != _peripheral.uuid) return;
      if (event.characteristic.uuid != stateCharacteristic.uuid) return;
      if (!_incoming.isClosed) _incoming.add(event.value);
    });

    _connectionSub = _manager.connectionStateChanged.listen((event) {
      if (event.peripheral.uuid != _peripheral.uuid) return;
      _setState(
        event.state == ble.ConnectionState.connected
            ? PeerConnectionState.connected
            : PeerConnectionState.disconnected,
      );
    });

    _mtuSub = _manager.mtuChanged.listen((event) {
      if (event.peripheral.uuid != _peripheral.uuid) return;
      // The MTU includes ATT overhead; the usable write payload is smaller.
      _maxChunkBytes = (event.mtu - _attWriteOverhead).clamp(
        _minChunkBytes,
        _maxSensibleChunkBytes,
      );
    });

    unawaited(_refreshWriteLength());
  }

  /// ATT write-request header (opcode + handle).
  static const int _attWriteOverhead = 3;
  static const int _minChunkBytes = 20;
  static const int _maxSensibleChunkBytes = 512;

  final ble.CentralManager _manager;
  final ble.Peripheral _peripheral;

  /// Host -> joiner notifications.
  final ble.GATTCharacteristic stateCharacteristic;

  /// Joiner -> host writes.
  final ble.GATTCharacteristic inputCharacteristic;

  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<PeerConnectionState> _stateChanges =
      StreamController<PeerConnectionState>.broadcast();

  StreamSubscription<ble.GATTCharacteristicNotifiedEventArgs>? _notifiedSub;
  StreamSubscription<ble.PeripheralConnectionStateChangedEventArgs>?
  _connectionSub;
  StreamSubscription<ble.PeripheralMTUChangedEventArgs>? _mtuSub;

  PeerConnectionState _state = PeerConnectionState.connected;
  int _maxChunkBytes = _minChunkBytes;

  @override
  String get peerId => _peripheral.uuid.toString();

  @override
  PeerConnectionState get state => _state;

  @override
  Stream<PeerConnectionState> get stateChanges => _stateChanges.stream;

  @override
  Stream<Uint8List> get incomingBytes => _incoming.stream;

  @override
  int get maxChunkBytes => _maxChunkBytes;

  @override
  Future<void> send(Uint8List chunk) async {
    if (_state != PeerConnectionState.connected) {
      throw const PeerConnectionClosed('peripheral link is down');
    }
    // Writes *with response* are what makes the stream ordered and reliable,
    // which the framing layer depends on (ADR-0010).
    await _manager.writeCharacteristic(
      _peripheral,
      inputCharacteristic,
      value: chunk,
      type: ble.GATTCharacteristicWriteType.withResponse,
    );
  }

  @override
  Future<void> close() async {
    await _notifiedSub?.cancel();
    await _connectionSub?.cancel();
    await _mtuSub?.cancel();
    try {
      await _manager.disconnect(_peripheral);
    } on Object catch (error) {
      debugPrint('_CentralPeerConnection: disconnect failed — $error');
    }
    _setState(PeerConnectionState.disconnected);
    if (!_incoming.isClosed) await _incoming.close();
    if (!_stateChanges.isClosed) await _stateChanges.close();
  }

  Future<void> _refreshWriteLength() async {
    try {
      final length = await _manager.getMaximumWriteLength(
        _peripheral,
        type: ble.GATTCharacteristicWriteType.withResponse,
      );
      _maxChunkBytes = length.clamp(_minChunkBytes, _maxSensibleChunkBytes);
    } on Object catch (error) {
      // Fall back to the unnegotiated minimum: slower, never wrong.
      debugPrint('_CentralPeerConnection: MTU query failed — $error');
    }
  }

  void _setState(PeerConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateChanges.isClosed) _stateChanges.add(next);
  }
}
