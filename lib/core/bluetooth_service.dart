import 'dart:async';

import 'package:bluetooth_connected_gaming/core/transport/ble/ble_readiness_mapping.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart' as ble;
import 'package:flutter/foundation.dart';

/// App-wide view of whether Bluetooth is usable, shared by the host and joiner
/// flows and by the "turn on Bluetooth" notice (#36).
///
/// This deliberately does not scan, advertise, or move bytes — that is the
/// radio adapters' job. It answers one question, continuously: can we play
/// right now, and if not, why not.
class BluetoothService extends ChangeNotifier {
  BluetoothService({ble.CentralManager? manager})
    : _manager = manager ?? ble.CentralManager() {
    _readiness = readinessFrom(_manager.state);
    _stateSub = _manager.stateChanged.listen((event) {
      _set(readinessFrom(event.state));
    });
  }

  /// The shared instance used by the app shell.
  static final BluetoothService instance = BluetoothService();

  final ble.CentralManager _manager;
  StreamSubscription<ble.BluetoothLowEnergyStateChangedEventArgs>? _stateSub;

  late BleReadiness _readiness;

  /// Current adapter readiness.
  BleReadiness get readiness => _readiness;

  /// Whether a session can be started right now.
  bool get isReady => _readiness == BleReadiness.ready;

  /// Request Bluetooth permission if the platform has not granted it yet, then
  /// report the resulting readiness.
  ///
  /// Safe to call repeatedly: it only prompts while the state is
  /// [BleReadiness.unauthorized].
  Future<BleReadiness> ensureReady() async {
    if (_manager.state == ble.BluetoothLowEnergyState.unauthorized) {
      try {
        await _manager.authorize();
      } on Object catch (error) {
        debugPrint('BluetoothService: authorize failed — $error');
      }
    }
    _set(readinessFrom(_manager.state));
    return _readiness;
  }

  /// Open the OS settings page for this app, so the user can grant Bluetooth
  /// permission after having denied it. There is no in-app recovery from a
  /// denied permission on either platform.
  Future<void> openSettings() async {
    try {
      await _manager.showAppSettings();
    } on Object catch (error) {
      debugPrint('BluetoothService: showAppSettings failed — $error');
    }
  }

  void _set(BleReadiness next) {
    if (_readiness == next) return;
    _readiness = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    super.dispose();
  }
}
