import 'dart:async';

import 'package:bluetooth_connected_gaming/core/display_name.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/session/handshake.dart';
import 'package:bluetooth_connected_gaming/core/session/session_launcher.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_host.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:flutter/foundation.dart';

/// The lobby flow as observable state. Sealed so the UI switches exhaustively
/// over every outcome.
sealed class LobbyState {
  const LobbyState();
}

/// Nothing started: the user picks Host or Join.
class LobbyIdle extends LobbyState {
  const LobbyIdle();
}

/// Advertising and waiting for a joiner to arrive.
class LobbyHosting extends LobbyState {
  const LobbyHosting(this.displayName);

  /// The name being advertised, shown so the user can read it out.
  final String displayName;
}

/// Scanning for hosts; [hosts] grows as they are discovered.
class LobbyScanning extends LobbyState {
  const LobbyScanning(this.hosts);

  /// Hosts found so far, deduplicated by id.
  final List<DiscoveredHost> hosts;
}

/// A link is being established and the handshake exchanged.
class LobbyConnecting extends LobbyState {
  const LobbyConnecting(this.peerLabel);

  /// What to call the other device while connecting.
  final String peerLabel;
}

/// A session is live and the game can start.
class LobbyReady extends LobbyState {
  const LobbyReady(this.session);

  /// The established session, handed to the game.
  final GameSession session;
}

/// The flow failed; [message] is user-facing and [canRetry] drives the button.
class LobbyFailed extends LobbyState {
  const LobbyFailed(this.message, {this.canRetry = true});

  /// What went wrong, in words a player can act on.
  final String message;

  /// Whether retrying could plausibly help.
  final bool canRetry;
}

/// Drives host-and-join to a live [GameSession] (#6, #13, #17).
///
/// Depends only on the [BleHost] / [BleScanner] interfaces and a
/// [SessionLauncher], so the whole flow — including both failure paths — is
/// unit-testable with fakes and no Bluetooth hardware.
class LobbyController extends ChangeNotifier {
  LobbyController({
    required BleHost host,
    required BleScanner scanner,
    SessionLauncher launcher = const SessionLauncher(),
  }) : _host = host,
       _scanner = scanner,
       _launcher = launcher;

  /// How long to look for hosts before giving up.
  static const Duration scanTimeout = Duration(seconds: 10);

  final BleHost _host;
  final BleScanner _scanner;
  final SessionLauncher _launcher;

  final List<DiscoveredHost> _hosts = <DiscoveredHost>[];
  StreamSubscription<DiscoveredHost>? _scanSub;
  StreamSubscription<PeerConnection>? _hostSub;

  LobbyState _state = const LobbyIdle();

  /// The current flow state.
  LobbyState get state => _state;

  /// Advertise under [displayName] and wait for a joiner (#6, host path).
  Future<void> startHosting(String displayName) async {
    if (_state is LobbyHosting || _state is LobbyConnecting) return;
    final name = sanitizeDisplayName(displayName, fallback: 'Player');

    final readiness = await _host.ensureReady();
    if (readiness != BleReadiness.ready) {
      _set(_readinessFailure(readiness));
      return;
    }

    _set(LobbyHosting(name));
    await _hostSub?.cancel();
    // Take the first joiner and stop advertising: NearPlay is a two-device
    // game, so a second joiner has nothing to join.
    _hostSub = _host.connections.listen(
      (connection) => unawaited(_onJoinerArrived(connection, name)),
      onError: (Object error) => _set(_hostFailure(error)),
    );

    try {
      await _host.startAdvertising(name);
    } on BleHostException catch (error) {
      _set(_hostFailure(error));
    }
  }

  /// Scan for hosts (#6, join path).
  Future<void> startScanning() async {
    if (_state is LobbyScanning || _state is LobbyConnecting) return;
    _hosts.clear();

    final readiness = await _scanner.ensureReady();
    if (readiness != BleReadiness.ready) {
      _set(_readinessFailure(readiness));
      return;
    }

    _set(const LobbyScanning(<DiscoveredHost>[]));
    await _scanSub?.cancel();
    _scanSub = _scanner
        .scan(timeout: scanTimeout)
        .listen(
          _onHostDiscovered,
          onError: _onScanError,
          onDone: _onScanDone,
        );
  }

  /// Connect to [discovered] and launch the session as the client.
  Future<void> join(DiscoveredHost discovered, String localName) async {
    if (_state is LobbyConnecting || _state is LobbyReady) return;
    await _stopScanning();

    final label = discovered.name.isNotEmpty ? discovered.name : discovered.id;
    _set(LobbyConnecting(label));

    final PeerConnection connection;
    try {
      connection = await _scanner.connect(discovered.id);
    } on BleException catch (error) {
      _set(LobbyFailed(_joinMessage(error.reason)));
      return;
    } on Object {
      _set(const LobbyFailed('Could not connect to that host. Try again.'));
      return;
    }

    await _launch(connection, PeerRole.client, localName);
  }

  /// Abandon whatever is in flight and return to the initial choice.
  Future<void> cancel() async {
    await _stopScanning();
    await _hostSub?.cancel();
    _hostSub = null;
    await _host.stopAdvertising();
    _set(const LobbyIdle());
  }

  Future<void> _onJoinerArrived(
    PeerConnection connection,
    String localName,
  ) async {
    if (_state is LobbyConnecting || _state is LobbyReady) return;
    // Withdraw the service, not just the advertisement: a central that saw an
    // earlier advertisement can still reach a published GATT server.
    await _host.stopAccepting();
    _set(LobbyConnecting(connection.peerId));
    await _launch(connection, PeerRole.host, localName);
  }

  Future<void> _launch(
    PeerConnection connection,
    PeerRole role,
    String localName,
  ) async {
    try {
      final session = await _launcher.launch(
        connection: connection,
        role: role,
        localName: localName,
      );
      _set(LobbyReady(session));
    } on HandshakeException catch (error) {
      _set(LobbyFailed(_handshakeMessage(error.failure)));
    } on Object {
      _set(const LobbyFailed('Could not start the game. Try again.'));
    }
  }

  void _onHostDiscovered(DiscoveredHost host) {
    final index = _hosts.indexWhere((h) => h.id == host.id);
    if (index >= 0) {
      _hosts[index] = host;
    } else {
      _hosts.add(host);
    }
    _set(LobbyScanning(List<DiscoveredHost>.unmodifiable(_hosts)));
  }

  void _onScanError(Object error, StackTrace stackTrace) {
    final reason = error is BleException
        ? error.reason
        : JoinFailureReason.unknown;
    _set(LobbyFailed(_joinMessage(reason)));
  }

  void _onScanDone() {
    // Only fall to "no host found" if the scan ran clean to completion: if a
    // host was found we are already showing it, and if it errored we are
    // already showing that.
    if (_state is LobbyScanning && _hosts.isEmpty) {
      _set(LobbyFailed(_joinMessage(JoinFailureReason.noHostFound)));
    }
  }

  Future<void> _stopScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await _scanner.stopScan();
  }

  LobbyFailed _readinessFailure(BleReadiness readiness) {
    return switch (readiness) {
      BleReadiness.ready => const LobbyFailed('Something went wrong.'),
      BleReadiness.unsupported => const LobbyFailed(
        "This device doesn't support Bluetooth, so it can't play NearPlay.",
        canRetry: false,
      ),
      BleReadiness.poweredOff => const LobbyFailed(
        'Bluetooth is off. Turn it on to play.',
      ),
      BleReadiness.unauthorized => const LobbyFailed(
        'NearPlay needs Bluetooth permission. Enable it in Settings, then '
        'try again.',
      ),
    };
  }

  LobbyFailed _hostFailure(Object error) {
    if (error is! BleHostException) {
      return const LobbyFailed('Could not start hosting. Try again.');
    }
    return switch (error.reason) {
      HostFailureReason.bluetoothUnsupported => const LobbyFailed(
        "This device doesn't support Bluetooth, so it can't play NearPlay.",
        canRetry: false,
      ),
      HostFailureReason.bluetoothOff => const LobbyFailed(
        'Bluetooth is off. Turn it on to host a game.',
      ),
      HostFailureReason.permissionDenied => const LobbyFailed(
        'NearPlay needs Bluetooth permission to host. Enable it in Settings, '
        'then try again.',
      ),
      HostFailureReason.advertisingFailed => const LobbyFailed(
        "This device can't advertise a game. Try joining instead.",
      ),
      HostFailureReason.unknown => const LobbyFailed(
        'Could not start hosting. Try again.',
      ),
    };
  }

  String _joinMessage(JoinFailureReason reason) {
    return switch (reason) {
      JoinFailureReason.bluetoothUnsupported =>
        "This device doesn't support Bluetooth.",
      JoinFailureReason.bluetoothOff =>
        'Bluetooth is off. Turn it on to find a game.',
      JoinFailureReason.permissionDenied =>
        'NearPlay needs Bluetooth permission. Enable it in Settings, then '
            'try again.',
      JoinFailureReason.noHostFound =>
        'No game found nearby. Make sure your friend has tapped Host.',
      JoinFailureReason.connectionRefused =>
        'Could not connect to that host. Try again.',
      JoinFailureReason.characteristicDiscoveryFailed =>
        "That device isn't hosting NearPlay. Try another.",
      JoinFailureReason.unknown => 'Something went wrong. Try again.',
    };
  }

  String _handshakeMessage(HandshakeFailure failure) {
    return switch (failure) {
      HandshakeFailure.timedOut =>
        "Connected, but the other player didn't respond. Try again.",
      HandshakeFailure.disconnected =>
        'The other player disconnected before the game started.',
      HandshakeFailure.roleConflict =>
        'You both tapped Host. One of you needs to tap Join.',
    };
  }

  void _set(LobbyState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_scanSub?.cancel());
    unawaited(_hostSub?.cancel());
    unawaited(_scanner.stopScan());
    unawaited(_host.dispose());
    super.dispose();
  }
}
