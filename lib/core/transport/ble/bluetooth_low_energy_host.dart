import 'dart:async';

import 'package:bluetooth_connected_gaming/core/transport/ble/ble_host.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_readiness_mapping.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/gatt_contract.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart' as ble;
import 'package:flutter/foundation.dart';

/// `bluetooth_low_energy`-backed [BleHost] — the host half of the radio layer
/// (#7, ADR-0009). The other of the two files that import the BLE package.
///
/// Publishes ADR-0006's service with its two characteristics, advertises the
/// service UUID, and hands out a [PeerConnection] once a joiner has connected
/// *and* subscribed to the state characteristic. Subscription is the real
/// readiness signal: until the joiner enables notifications the host has no way
/// to push a frame, so emitting earlier would hand out a half-open channel.
///
/// **Not unit-tested**: it talks to hardware. Validated per the #26 runbook.
class BluetoothLowEnergyHost implements BleHost {
  BluetoothLowEnergyHost({ble.PeripheralManager? manager})
    : _manager = manager ?? ble.PeripheralManager();

  final ble.PeripheralManager _manager;

  final ble.UUID _serviceUuid = ble.UUID.fromString(GattContract.serviceUuid);

  late final ble.GATTCharacteristic _stateCharacteristic =
      ble.GATTCharacteristic.mutable(
        uuid: ble.UUID.fromString(GattContract.stateCharacteristicUuid),
        properties: const <ble.GATTCharacteristicProperty>[
          ble.GATTCharacteristicProperty.notify,
        ],
        // Notify-only: a joiner must never be able to read back or overwrite
        // authoritative state, only receive what the host pushes (ADR-0003).
        permissions: const <ble.GATTCharacteristicPermission>[],
        descriptors: const <ble.GATTDescriptor>[],
      );

  late final ble.GATTCharacteristic _inputCharacteristic =
      ble.GATTCharacteristic.mutable(
        uuid: ble.UUID.fromString(GattContract.inputCharacteristicUuid),
        properties: const <ble.GATTCharacteristicProperty>[
          ble.GATTCharacteristicProperty.write,
        ],
        permissions: const <ble.GATTCharacteristicPermission>[
          ble.GATTCharacteristicPermission.write,
        ],
        descriptors: const <ble.GATTDescriptor>[],
      );

  final StreamController<PeerConnection> _connections =
      StreamController<PeerConnection>.broadcast();

  final Map<String, _HostPeerConnection> _live =
      <String, _HostPeerConnection>{};

  StreamSubscription<ble.GATTCharacteristicNotifyStateChangedEventArgs>?
  _notifySub;
  StreamSubscription<ble.GATTCharacteristicWriteRequestedEventArgs>? _writeSub;
  StreamSubscription<ble.CentralConnectionStateChangedEventArgs>?
  _connectionSub;
  StreamSubscription<ble.CentralMTUChangedEventArgs>? _mtuSub;

  bool _advertising = false;

  @override
  Stream<PeerConnection> get connections => _connections.stream;

  @override
  Future<BleReadiness> ensureReady() async {
    if (_manager.state == ble.BluetoothLowEnergyState.unsupported) {
      return BleReadiness.unsupported;
    }
    if (_manager.state == ble.BluetoothLowEnergyState.unauthorized) {
      await _manager.authorize();
    }
    return readinessFrom(_manager.state);
  }

  @override
  Future<void> startAdvertising(String displayName) async {
    if (_advertising) return;
    _listen();

    try {
      // Republish from scratch: a stale service from a previous session would
      // advertise characteristics this host is no longer serving.
      await _manager.removeAllServices();
      await _manager.addService(
        ble.GATTService(
          uuid: _serviceUuid,
          isPrimary: true,
          includedServices: const <ble.GATTService>[],
          characteristics: <ble.GATTCharacteristic>[
            _stateCharacteristic,
            _inputCharacteristic,
          ],
        ),
      );
      // The service UUID must be in the advertisement itself, not only in the
      // GATT table — iOS centrals can only scan by advertised service
      // (ADR-0006).
      await _manager.startAdvertising(
        ble.Advertisement(
          name: displayName,
          serviceUUIDs: <ble.UUID>[_serviceUuid],
        ),
      );
      _advertising = true;
    } on Object catch (error) {
      throw BleHostException(HostFailureReason.advertisingFailed, '$error');
    }
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_advertising) return;
    _advertising = false;
    try {
      await _manager.stopAdvertising();
    } on Object catch (error) {
      debugPrint('BluetoothLowEnergyHost: stopAdvertising failed — $error');
    }
  }

  @override
  Future<void> dispose() async {
    await stopAdvertising();
    await _notifySub?.cancel();
    await _writeSub?.cancel();
    await _connectionSub?.cancel();
    await _mtuSub?.cancel();
    for (final connection in _live.values.toList()) {
      await connection.close();
    }
    _live.clear();
    try {
      await _manager.removeAllServices();
    } on Object catch (error) {
      debugPrint('BluetoothLowEnergyHost: removeAllServices failed — $error');
    }
    if (!_connections.isClosed) await _connections.close();
  }

  void _listen() {
    _notifySub ??= _manager.characteristicNotifyStateChanged.listen((event) {
      if (event.characteristic.uuid != _stateCharacteristic.uuid) return;
      final id = event.central.uuid.toString();
      if (event.state) {
        _onJoinerReady(event.central, id);
      } else {
        // The joiner turned notifications off: it can no longer be sent state,
        // so the session is over as far as the host is concerned.
        unawaited(_dropCentral(id));
      }
    });

    _writeSub ??= _manager.characteristicWriteRequested.listen((event) async {
      final id = event.central.uuid.toString();
      final connection = _live[id];
      // Always answer the request — an unanswered write stalls the joiner's
      // ordered stream, which the framing layer depends on.
      await _respond(event.request);
      if (event.characteristic.uuid != _inputCharacteristic.uuid) return;
      connection?.deliver(event.request.value);
    });

    _connectionSub ??= _manager.connectionStateChanged.listen((event) {
      if (event.state == ble.ConnectionState.disconnected) {
        unawaited(_dropCentral(event.central.uuid.toString()));
      }
    });

    _mtuSub ??= _manager.mtuChanged.listen((event) {
      _live[event.central.uuid.toString()]?.updateMtu(event.mtu);
    });
  }

  void _onJoinerReady(ble.Central central, String id) {
    if (_live.containsKey(id)) return;
    final connection = _HostPeerConnection(
      manager: _manager,
      central: central,
      stateCharacteristic: _stateCharacteristic,
      onClosed: () => _live.remove(id),
    );
    _live[id] = connection;
    unawaited(connection.refreshNotifyLength());
    if (!_connections.isClosed) _connections.add(connection);
  }

  Future<void> _dropCentral(String id) async {
    final connection = _live.remove(id);
    if (connection == null) return;
    await connection.close();
  }

  Future<void> _respond(ble.GATTWriteRequest request) async {
    try {
      await _manager.respondWriteRequest(request);
    } on Object catch (error) {
      debugPrint('BluetoothLowEnergyHost: respondWriteRequest failed — $error');
    }
  }
}

/// The host's side of the byte channel: inbound bytes are writes the joiner
/// makes to the input characteristic, outbound bytes are notifications on the
/// state characteristic (ADR-0006).
class _HostPeerConnection implements PeerConnection {
  _HostPeerConnection({
    required ble.PeripheralManager manager,
    required ble.Central central,
    required this.stateCharacteristic,
    required VoidCallback onClosed,
  }) : _manager = manager,
       _central = central,
       _onClosed = onClosed;

  /// ATT notification header (opcode + handle).
  static const int _attNotifyOverhead = 3;
  static const int _minChunkBytes = 20;
  static const int _maxSensibleChunkBytes = 512;

  final ble.PeripheralManager _manager;
  final ble.Central _central;
  final VoidCallback _onClosed;

  /// Host -> joiner notifications.
  final ble.GATTCharacteristic stateCharacteristic;

  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<PeerConnectionState> _stateChanges =
      StreamController<PeerConnectionState>.broadcast();

  PeerConnectionState _state = PeerConnectionState.connected;
  int _maxChunkBytes = _minChunkBytes;

  @override
  String get peerId => _central.uuid.toString();

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
      throw const PeerConnectionClosed('central link is down');
    }
    await _manager.notifyCharacteristic(
      _central,
      stateCharacteristic,
      value: chunk,
    );
  }

  /// Push bytes the joiner wrote onto the inbound stream.
  void deliver(Uint8List bytes) {
    if (!_incoming.isClosed) _incoming.add(bytes);
  }

  /// Re-clamp the chunk size after an MTU renegotiation.
  void updateMtu(int mtu) {
    _maxChunkBytes = (mtu - _attNotifyOverhead).clamp(
      _minChunkBytes,
      _maxSensibleChunkBytes,
    );
  }

  /// Ask the platform how many bytes fit in one notification.
  Future<void> refreshNotifyLength() async {
    try {
      final length = await _manager.getMaximumNotifyLength(_central);
      _maxChunkBytes = length.clamp(_minChunkBytes, _maxSensibleChunkBytes);
    } on Object catch (error) {
      debugPrint('_HostPeerConnection: notify-length query failed — $error');
    }
  }

  @override
  Future<void> close() async {
    _onClosed();
    try {
      await _manager.disconnect(_central);
    } on Object catch (error) {
      debugPrint('_HostPeerConnection: disconnect failed — $error');
    }
    if (_state != PeerConnectionState.disconnected) {
      _state = PeerConnectionState.disconnected;
      if (!_stateChanges.isClosed) {
        _stateChanges.add(PeerConnectionState.disconnected);
      }
    }
    if (!_incoming.isClosed) await _incoming.close();
    if (!_stateChanges.isClosed) await _stateChanges.close();
  }
}
