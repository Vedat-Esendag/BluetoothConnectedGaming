import 'dart:async';

import 'package:bluetooth_connected_gaming/core/display_name.dart';
import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/session/session_launcher.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_host.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/bluetooth_low_energy_host.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/bluetooth_low_energy_scanner.dart';
import 'package:bluetooth_connected_gaming/shell/lobby/lobby_controller.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_tokens.dart';
import 'package:flutter/material.dart';

/// Host-or-join for one mini-game (#6), ending in a live session handed to the
/// game (#17).
///
/// Both players see the same screen and one of them taps Host. Everything
/// downstream — advertising or scanning, connecting, the handshake — is
/// [LobbyController]'s; this widget only renders its state and collects a name.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    required this.game,
    this.host,
    this.scanner,
    this.launcher,
    super.key,
  });

  /// The game this session is for.
  final MiniGameDescriptor game;

  /// Injectable radio backends; the real adapters are used when omitted, so
  /// tests can drive the whole flow without Bluetooth hardware.
  final BleHost? host;
  final BleScanner? scanner;

  /// Injectable session launcher, so a test can reach the hand-off without
  /// standing up a second device to answer the handshake.
  final SessionLauncher? launcher;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final LobbyController _controller = LobbyController(
    host: widget.host ?? BluetoothLowEnergyHost(),
    scanner: widget.scanner ?? BluetoothLowEnergyScanner(),
    launcher: widget.launcher ?? const SessionLauncher(),
  );
  final TextEditingController _nameField = TextEditingController(
    text: 'Player',
  );

  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onStateChanged)
      ..dispose();
    _nameField.dispose();
    super.dispose();
  }

  /// Hand the live session to the game exactly once.
  void _onStateChanged() {
    final state = _controller.state;
    if (state is! LobbyReady || _handedOff) return;
    _handedOff = true;
    unawaited(_openGame(state.session));
  }

  /// Push the game *over* the lobby rather than replacing it.
  ///
  /// This is load-bearing, not a navigation preference. On the host side the
  /// radio is owned by this screen's controller, and the connection handed to
  /// the game is the same object the `BleHost` is serving — so replacing this
  /// route would dispose the controller, dispose the host, and close the
  /// connection the game had just been given. The lobby therefore stays
  /// mounted underneath for as long as the match lasts.
  Future<void> _openGame(GameSession session) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => widget.game.build(context, session: session),
      ),
    );

    // Back from the game — either it ended or the player navigated out of a
    // still-live match. Either way the session is over, and saying so is what
    // stops the peer sitting there believing the game is still running.
    await session.transport.disconnect();
    if (!mounted) return;
    _handedOff = false;
    await _controller.cancel();
  }

  String get _name => sanitizeDisplayName(_nameField.text, fallback: 'Player');

  void _host() => unawaited(_controller.startHosting(_name));
  void _scan() => unawaited(_controller.startScanning());
  void _cancel() => unawaited(_controller.cancel());
  void _join(DiscoveredHost host) => unawaited(_controller.join(host, _name));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.game.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NearPlaySpacing.lg),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _buildState(_controller.state),
          ),
        ),
      ),
    );
  }

  Widget _buildState(LobbyState state) {
    return switch (state) {
      LobbyIdle() => _chooser(),
      LobbyHosting(:final displayName) => _waiting(
        title: 'Waiting for a player',
        detail:
            'Ask them to open ${widget.game.title} and tap Join. '
            'You appear as "$displayName".',
        onCancel: _cancel,
      ),
      LobbyScanning(:final hosts) => _hostList(hosts),
      LobbyConnecting(:final peerLabel) => _waiting(
        title: 'Connecting',
        detail: 'Setting up the game with $peerLabel…',
      ),
      LobbyReady() => _waiting(title: 'Starting', detail: 'Here we go…'),
      LobbyFailed(:final message, :final canRetry) => _failure(
        message,
        canRetry: canRetry,
      ),
    };
  }

  Widget _chooser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Play together', style: NearPlayText.display),
        const SizedBox(height: NearPlaySpacing.sm),
        const Text(
          'Two phones, no internet. One of you hosts, the other joins.',
          style: NearPlayText.body,
        ),
        const SizedBox(height: NearPlaySpacing.xl),
        TextField(
          controller: _nameField,
          maxLength: maxDisplayNameLength,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Your name',
            counterText: '',
          ),
        ),
        const SizedBox(height: NearPlaySpacing.xl),
        FilledButton(onPressed: _host, child: const Text('Host a game')),
        const SizedBox(height: NearPlaySpacing.md),
        OutlinedButton(onPressed: _scan, child: const Text('Join a game')),
      ],
    );
  }

  Widget _waiting({
    required String title,
    required String detail,
    VoidCallback? onCancel,
  }) {
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: NearPlaySpacing.xl),
            Text(title, style: NearPlayText.title),
            const SizedBox(height: NearPlaySpacing.sm),
            Text(detail, style: NearPlayText.body, textAlign: TextAlign.center),
            if (onCancel != null) ...[
              const SizedBox(height: NearPlaySpacing.xl),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hostList(List<DiscoveredHost> hosts) {
    if (hosts.isEmpty) {
      return _waiting(
        title: 'Looking for a game',
        detail: 'Make sure your friend has tapped Host.',
        onCancel: _cancel,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Nearby games', style: NearPlayText.title),
        const SizedBox(height: NearPlaySpacing.md),
        Expanded(
          child: ListView.separated(
            itemCount: hosts.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: NearPlaySpacing.sm),
            itemBuilder: (context, i) => _HostTile(
              host: hosts[i],
              onTap: () => _join(hosts[i]),
            ),
          ),
        ),
        TextButton(onPressed: _cancel, child: const Text('Cancel')),
      ],
    );
  }

  Widget _failure(String message, {required bool canRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: NearPlayColors.alert,
          ),
          const SizedBox(height: NearPlaySpacing.lg),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: NearPlayText.body,
              textAlign: TextAlign.center,
            ),
          ),
          if (canRetry) ...[
            const SizedBox(height: NearPlaySpacing.xl),
            FilledButton(
              onPressed: _cancel,
              child: const Text('Back'),
            ),
          ],
        ],
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({required this.host, required this.onTap});

  final DiscoveredHost host;
  final VoidCallback onTap;

  /// Rough distance cue from signal strength. Deliberately coarse: RSSI is
  /// noisy, and the only question a player has is "is that the phone next to
  /// me?".
  String get _proximity {
    if (host.rssi >= -55) return 'Right here';
    if (host.rssi >= -75) return 'Nearby';
    return 'Far away';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.sports_esports_outlined),
        title: Text(host.name.isNotEmpty ? host.name : 'Unnamed game'),
        subtitle: Text(_proximity),
        trailing: const Icon(Icons.chevron_right),
        shape: const RoundedRectangleBorder(
          borderRadius: NearPlayRadius.cardBorder,
        ),
        onTap: onTap,
      ),
    );
  }
}
