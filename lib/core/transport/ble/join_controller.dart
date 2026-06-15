import 'dart:async';

import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:flutter/foundation.dart';

/// The joiner's scan -> connect flow as observable state. Sealed so the UI can
/// switch exhaustively over every outcome.
sealed class JoinState {
  const JoinState();
}

/// Nothing started yet.
class JoinIdle extends JoinState {
  const JoinIdle();
}

/// A scan is in progress and no host has been found yet.
class JoinScanning extends JoinState {
  const JoinScanning();
}

/// One or more hosts have been discovered; the user picks one.
class JoinFoundHosts extends JoinState {
  const JoinFoundHosts(this.hosts);

  /// Discovered hosts, deduplicated by [DiscoveredHost.id].
  final List<DiscoveredHost> hosts;
}

/// Connecting to (and discovering characteristics on) [host].
class JoinConnecting extends JoinState {
  const JoinConnecting(this.host);

  /// The host being connected to.
  final DiscoveredHost host;
}

/// Connected; [connection] exposes the discovered characteristics.
class JoinConnected extends JoinState {
  const JoinConnected(this.connection);

  /// The established connection (provisional surface — see ADR-0006).
  final BleConnection connection;
}

/// The attempt failed for [reason]; the UI shows a message + recovery action.
class JoinFailed extends JoinState {
  const JoinFailed(this.reason);

  /// Why the attempt failed.
  final JoinFailureReason reason;
}

/// Drives the joiner flow over a [BleScanner], exposing it as [JoinState].
///
/// Depends only on the [BleScanner] interface, so it is fully unit-testable
/// with a mock — no Bluetooth hardware required.
class JoinController extends ChangeNotifier {
  JoinController(this._scanner);

  final BleScanner _scanner;
  final List<DiscoveredHost> _hosts = <DiscoveredHost>[];
  StreamSubscription<DiscoveredHost>? _scanSub;

  JoinState _state = const JoinIdle();

  /// The current flow state.
  JoinState get state => _state;

  /// Begin scanning. Checks readiness first; on a non-ready stack it fails fast
  /// with the mapped reason and never starts a scan. Safe to call again to
  /// retry from a failed/idle/found state.
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_state is JoinScanning || _state is JoinConnecting) return;
    _hosts.clear();

    final readiness = await _scanner.ensureReady();
    if (readiness != BleReadiness.ready) {
      _set(JoinFailed(_reasonForReadiness(readiness)));
      return;
    }

    _set(const JoinScanning());
    await _scanSub?.cancel();
    _scanSub = _scanner
        .scan(timeout: timeout)
        .listen(
          _onHostDiscovered,
          onError: _onScanError,
          onDone: _onScanDone,
        );
  }

  /// Stop scanning and connect to [host], discovering its characteristics.
  Future<void> connectToHost(DiscoveredHost host) async {
    await _scanSub?.cancel();
    _scanSub = null;
    await _scanner.stopScan();

    _set(JoinConnecting(host));
    try {
      final connection = await _scanner.connect(host.id);
      _set(JoinConnected(connection));
    } on BleException catch (e) {
      _set(JoinFailed(e.reason));
    } on Object {
      _set(const JoinFailed(JoinFailureReason.unknown));
    }
  }

  void _onHostDiscovered(DiscoveredHost host) {
    final index = _hosts.indexWhere((h) => h.id == host.id);
    if (index >= 0) {
      _hosts[index] = host;
    } else {
      _hosts.add(host);
    }
    _set(JoinFoundHosts(List<DiscoveredHost>.unmodifiable(_hosts)));
  }

  void _onScanError(Object error, StackTrace stackTrace) {
    final reason = error is BleException
        ? error.reason
        : JoinFailureReason.unknown;
    _set(JoinFailed(reason));
  }

  void _onScanDone() {
    // Only fall to "no host found" if the scan ran clean to completion. If a
    // host was found we're already in JoinFoundHosts; if the stream errored
    // we're already in JoinFailed — neither should be overwritten here.
    if (_state is JoinScanning && _hosts.isEmpty) {
      _set(const JoinFailed(JoinFailureReason.noHostFound));
    }
  }

  JoinFailureReason _reasonForReadiness(BleReadiness readiness) {
    return switch (readiness) {
      BleReadiness.ready => JoinFailureReason.unknown,
      BleReadiness.unsupported => JoinFailureReason.bluetoothUnsupported,
      BleReadiness.poweredOff => JoinFailureReason.bluetoothOff,
      BleReadiness.unauthorized => JoinFailureReason.permissionDenied,
    };
  }

  void _set(JoinState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    final sub = _scanSub;
    if (sub != null) unawaited(sub.cancel());
    unawaited(_scanner.stopScan());
    super.dispose();
  }
}
