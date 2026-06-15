import 'dart:async';

import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/flutter_blue_plus_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/join_controller.dart';
import 'package:flutter/material.dart';

/// Minimal join flow for #8: scan for a host, pick one, connect, and surface
/// every outcome — success and each failure — with a clear message and a
/// recovery action.
///
/// The full lobby / host-and-join screen is #6; the polished "turn on
/// Bluetooth" prompt is #36. This screen owns its [JoinController].
class JoinScreen extends StatefulWidget {
  const JoinScreen({this.scanner, super.key});

  /// Injectable BLE backend; defaults to the real `flutter_blue_plus` adapter.
  /// Tests pass a mock so the whole flow runs without Bluetooth hardware.
  final BleScanner? scanner;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late final JoinController _controller = JoinController(
    widget.scanner ?? FlutterBluePlusScanner(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scan() => unawaited(_controller.startScan());

  void _connect(DiscoveredHost host) =>
      unawaited(_controller.connectToHost(host));

  String _hostLabel(DiscoveredHost host) =>
      host.name.isNotEmpty ? host.name : host.id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a game')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _buildState(_controller.state),
          ),
        ),
      ),
    );
  }

  Widget _buildState(JoinState state) {
    return switch (state) {
      JoinIdle() => _prompt(
        icon: Icons.bluetooth_searching,
        message: 'Find a nearby host to join.',
        actionLabel: 'Scan for a host',
      ),
      JoinScanning() => _status(
        semanticsLabel: 'Scanning for nearby Bluetooth hosts',
        message: 'Searching for a host…',
        showSpinner: true,
      ),
      JoinFoundHosts(:final hosts) => _hostList(hosts),
      JoinConnecting(:final host) => _status(
        semanticsLabel: 'Connecting to a host',
        message: 'Connecting to ${_hostLabel(host)}…',
        showSpinner: true,
      ),
      JoinConnected(:final connection) => _status(
        icon: Icons.check_circle_outline,
        semanticsLabel: 'Connected',
        message: 'Connected to ${connection.deviceId}.',
      ),
      JoinFailed(:final reason) => _failure(reason),
    };
  }

  Widget _prompt({
    required IconData icon,
    required String message,
    required String actionLabel,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _scan, child: Text(actionLabel)),
      ],
    );
  }

  Widget _status({
    required String semanticsLabel,
    required String message,
    IconData? icon,
    bool showSpinner = false,
  }) {
    return Semantics(
      label: semanticsLabel,
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner) const CircularProgressIndicator(),
          if (icon != null) Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _hostList(List<DiscoveredHost> hosts) {
    return Column(
      children: [
        Text(
          'Tap a host to connect',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: hosts.length,
            itemBuilder: (context, i) {
              final host = hosts[i];
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(_hostLabel(host)),
                subtitle: Text('Signal ${host.rssi} dBm'),
                onTap: () => _connect(host),
              );
            },
          ),
        ),
        TextButton(onPressed: _scan, child: const Text('Scan again')),
      ],
    );
  }

  Widget _failure(JoinFailureReason reason) {
    final view = _failureView(reason);
    final actionLabel = view.actionLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(view.icon, size: 48),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(view.message, textAlign: TextAlign.center),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _scan, child: Text(actionLabel)),
        ],
      ],
    );
  }

  /// Maps each failure to a specific icon, message, and recovery label. A null
  /// `actionLabel` means there is no recovery (e.g. no BLE hardware). Every
  /// recovery re-runs the scan, which on Android also re-attempts enabling the
  /// adapter and requesting permission via the readiness gate.
  ({IconData icon, String message, String? actionLabel}) _failureView(
    JoinFailureReason reason,
  ) {
    return switch (reason) {
      JoinFailureReason.bluetoothUnsupported => (
        icon: Icons.bluetooth_disabled,
        message: "This device doesn't support Bluetooth.",
        actionLabel: null,
      ),
      JoinFailureReason.bluetoothOff => (
        icon: Icons.bluetooth_disabled,
        message: 'Bluetooth is off. Turn it on to find a host.',
        actionLabel: 'Turn on Bluetooth',
      ),
      JoinFailureReason.permissionDenied => (
        icon: Icons.lock_outline,
        message:
            'NearPlay needs Bluetooth permission. Enable it in '
            'Settings, then try again.',
        actionLabel: 'Try again',
      ),
      JoinFailureReason.noHostFound => (
        icon: Icons.search_off,
        message:
            'No host found nearby. Make sure your friend has started a game.',
        actionLabel: 'Scan again',
      ),
      JoinFailureReason.connectionRefused => (
        icon: Icons.link_off,
        message: 'Could not connect to that host. Try again.',
        actionLabel: 'Try again',
      ),
      JoinFailureReason.characteristicDiscoveryFailed => (
        icon: Icons.help_outline,
        message: "That device isn't a NearPlay host. Try another.",
        actionLabel: 'Scan again',
      ),
      JoinFailureReason.unknown => (
        icon: Icons.error_outline,
        message: 'Something went wrong. Try again.',
        actionLabel: 'Try again',
      ),
    };
  }
}
