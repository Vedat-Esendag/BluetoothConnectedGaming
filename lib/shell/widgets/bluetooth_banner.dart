import 'dart:async';

import 'package:bluetooth_connected_gaming/core/bluetooth_service.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_tokens.dart';
import 'package:flutter/material.dart';

/// A banner that appears whenever Bluetooth is not usable (#36).
///
/// NearPlay is unplayable without the radio, so this is shown before the user
/// picks a game rather than after they have tried and failed. It watches the
/// adapter continuously, so turning Bluetooth off *while the app is open*
/// surfaces immediately and turning it back on dismisses the banner without a
/// retry tap.
class BluetoothBanner extends StatefulWidget {
  const BluetoothBanner({this.service, super.key});

  /// Injectable for tests; defaults to the app-wide service.
  final BluetoothService? service;

  @override
  State<BluetoothBanner> createState() => _BluetoothBannerState();
}

class _BluetoothBannerState extends State<BluetoothBanner> {
  late final BluetoothService _service =
      widget.service ?? BluetoothService.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        if (_service.isReady) return const SizedBox.shrink();
        return _Banner(
          readiness: _service.readiness,
          onFix: () => unawaited(_fix(_service.readiness)),
        );
      },
    );
  }

  Future<void> _fix(BleReadiness readiness) async {
    if (readiness == BleReadiness.unauthorized) {
      // A denied permission cannot be re-requested in-app on either platform.
      await _service.openSettings();
      return;
    }
    await _service.ensureReady();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.readiness, required this.onFix});

  final BleReadiness readiness;
  final VoidCallback onFix;

  ({String message, String? action}) get _copy {
    return switch (readiness) {
      BleReadiness.ready => (message: '', action: null),
      BleReadiness.unsupported => (
        message:
            "This device doesn't have Bluetooth, so NearPlay can't "
            'connect to another phone.',
        action: null,
      ),
      BleReadiness.poweredOff => (
        message: 'Bluetooth is off. Turn it on to play with someone nearby.',
        action: 'Check again',
      ),
      BleReadiness.unauthorized => (
        message: 'NearPlay needs Bluetooth permission to find nearby players.',
        action: 'Open Settings',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final action = copy.action;

    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(NearPlaySpacing.lg),
        padding: const EdgeInsets.all(NearPlaySpacing.lg),
        decoration: BoxDecoration(
          color: NearPlayColors.surfaceRaised,
          borderRadius: NearPlayRadius.cardBorder,
          border: Border.all(color: NearPlayColors.alert),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.bluetooth_disabled,
              color: NearPlayColors.alert,
            ),
            const SizedBox(width: NearPlaySpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(copy.message, style: NearPlayText.body),
                  if (action != null) ...[
                    const SizedBox(height: NearPlaySpacing.sm),
                    TextButton(onPressed: onFix, child: Text(action)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
