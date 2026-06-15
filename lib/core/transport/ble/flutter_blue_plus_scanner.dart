import 'dart:async';

import 'package:bluetooth_connected_gaming/core/bluetooth_service.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/gatt_contract.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

/// `flutter_blue_plus`-backed [BleScanner] — the only file that imports the
/// radio backend (prefixed `fbp` to avoid clashing with this app's own
/// [BluetoothService]).
///
/// **Not unit-tested**: it talks to hardware. Validated on real devices per the
/// #26 smoke-test runbook. Until the host (#7) exists nothing advertises the
/// service, so scans find nothing and the joiner lands on
/// [JoinFailureReason.noHostFound]; exercise it with the nRF Connect app set to
/// advertise the GATT contract.
class FlutterBluePlusScanner implements BleScanner {
  FlutterBluePlusScanner({BluetoothService? bluetooth})
    : _bluetooth = bluetooth ?? BluetoothService.instance;

  final BluetoothService _bluetooth;
  final fbp.Guid _serviceGuid = fbp.Guid(GattContract.serviceUuid);

  @override
  Future<BleReadiness> ensureReady() async {
    if (!await fbp.FlutterBluePlus.isSupported) {
      return BleReadiness.unsupported;
    }
    // Turn the adapter on where the platform permits (Android); delegate to the
    // shared service rather than re-implementing enable logic.
    await _bluetooth.initialise();
    final state = await fbp.FlutterBluePlus.adapterState.firstWhere(
      (s) => s != fbp.BluetoothAdapterState.unknown,
    );
    return switch (state) {
      fbp.BluetoothAdapterState.on => BleReadiness.ready,
      fbp.BluetoothAdapterState.unauthorized => BleReadiness.unauthorized,
      fbp.BluetoothAdapterState.unavailable => BleReadiness.unsupported,
      _ => BleReadiness.poweredOff,
    };
  }

  @override
  Stream<DiscoveredHost> scan({required Duration timeout}) {
    final controller = StreamController<DiscoveredHost>();
    final seen = <String>{};
    StreamSubscription<List<fbp.ScanResult>>? resultsSub;
    StreamSubscription<bool>? scanningSub;

    controller.onCancel = () async {
      await resultsSub?.cancel();
      await scanningSub?.cancel();
      await stopScan();
    };

    Future<void> start() async {
      // Subscribe before starting so no early advertisement is missed.
      resultsSub = fbp.FlutterBluePlus.onScanResults.listen(
        (results) {
          for (final r in results) {
            final id = r.device.remoteId.str;
            if (!seen.add(id)) continue;
            final advName = r.device.advName;
            controller.add(
              DiscoveredHost(
                id: id,
                name: advName.isNotEmpty ? advName : r.device.platformName,
                rssi: r.rssi,
              ),
            );
          }
        },
        onError: (Object e, StackTrace _) {
          if (!controller.isClosed) controller.addError(_mapScanError(e));
        },
      );

      try {
        await fbp.FlutterBluePlus.startScan(
          withServices: [_serviceGuid],
          timeout: timeout,
        );
      } on Object catch (e) {
        if (!controller.isClosed) {
          controller.addError(_mapScanError(e));
          unawaited(controller.close());
        }
        return;
      }

      // The scan is now running; close the stream when it next stops (the
      // timeout fires or stopScan is called). Subscribing here — after the
      // started=true emission — avoids the replayed initial value closing us
      // immediately.
      scanningSub = fbp.FlutterBluePlus.isScanning
          .where((scanning) => !scanning)
          .listen((_) {
            if (!controller.isClosed) unawaited(controller.close());
          });
    }

    unawaited(start());
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    if (fbp.FlutterBluePlus.isScanningNow) {
      await fbp.FlutterBluePlus.stopScan();
    }
  }

  @override
  Future<BleConnection> connect(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    try {
      // flutter_blue_plus 2.x requires declaring a license tier; NearPlay is a
      // personal/educational project, so nonprofit use applies.
      await device.connect(license: fbp.License.nonprofit);
    } on Object catch (e) {
      throw BleException(JoinFailureReason.connectionRefused, '$e');
    }

    final services = await device.discoverServices();
    final stateGuid = fbp.Guid(GattContract.stateCharacteristicUuid);
    final inputGuid = fbp.Guid(GattContract.inputCharacteristicUuid);

    fbp.BluetoothService? service;
    for (final s in services) {
      if (s.uuid == _serviceGuid) {
        service = s;
        break;
      }
    }

    final characteristics =
        service?.characteristics ?? const <fbp.BluetoothCharacteristic>[];
    final hasState = characteristics.any((c) => c.uuid == stateGuid);
    final hasInput = characteristics.any((c) => c.uuid == inputGuid);

    if (service == null || !hasState || !hasInput) {
      await device.disconnect();
      throw const BleException(JoinFailureReason.characteristicDiscoveryFailed);
    }

    return _FbpConnection(
      device,
      characteristics.map((c) => c.uuid.str).toList(),
    );
  }

  Object _mapScanError(Object error) {
    // Best-effort: on Android a denied scan permission surfaces here. Refine the
    // classification against real devices (#26).
    final text = '$error'.toLowerCase();
    if (text.contains('permission') || text.contains('unauthorized')) {
      return const BleException(JoinFailureReason.permissionDenied);
    }
    return BleException(JoinFailureReason.unknown, '$error');
  }
}

class _FbpConnection implements BleConnection {
  _FbpConnection(this._device, this.characteristicUuids);

  final fbp.BluetoothDevice _device;

  @override
  final List<String> characteristicUuids;

  @override
  String get deviceId => _device.remoteId.str;

  @override
  Future<void> disconnect() => _device.disconnect();
}
