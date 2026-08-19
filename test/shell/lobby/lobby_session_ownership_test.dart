import 'dart:async';

import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/session/session_launcher.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_host.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection_transport.dart';
import 'package:bluetooth_connected_gaming/shell/lobby/lobby_screen.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/loopback_peer_connection.dart';

class _MockBleScanner extends Mock implements BleScanner {}

/// A host that behaves like the real adapter in the one way that matters here:
/// **disposing it closes the connection it handed out.**
///
/// That is true of `BluetoothLowEnergyHost` — its GATT service and platform
/// subscriptions are what serve the live link — and a plain mock that only
/// records the call cannot catch a lobby that disposes too early.
class _OwningFakeHost implements BleHost {
  _OwningFakeHost(this._connection);

  final LoopbackPeerConnection _connection;
  final StreamController<PeerConnection> _connections =
      StreamController<PeerConnection>.broadcast();

  bool disposed = false;

  void emitJoiner() => _connections.add(_connection);

  @override
  Stream<PeerConnection> get connections => _connections.stream;

  @override
  Future<BleReadiness> ensureReady() async => BleReadiness.ready;

  @override
  Future<void> startAdvertising(String displayName) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> stopAccepting() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    // The real adapter takes the link down with itself.
    await _connection.close();
    await _connections.close();
  }
}

/// Skips the handshake: this test is about who owns the connection afterwards,
/// which `handshake_test.dart` has no opinion on.
class _ImmediateLauncher implements SessionLauncher {
  const _ImmediateLauncher();

  @override
  Future<GameSession> launch({
    required PeerConnection connection,
    required PeerRole role,
    required String localName,
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) async => GameSession(
    transport: PeerConnectionTransport(
      connection: connection,
      localPeerId: 'host-test',
    ),
    role: role,
    localPlayerId: 'host-test',
    localPlayerName: localName,
    remotePlayerName: 'Sam',
  );
}

class _ProbeGame implements MiniGameDescriptor {
  const _ProbeGame(this.probe);

  final void Function(GameSession session) probe;

  @override
  String get id => 'probe';

  @override
  String get title => 'Probe';

  @override
  bool get supportsMultiplayer => true;

  @override
  int get minPlayers => 2;

  @override
  int get maxPlayers => 2;

  @override
  Widget build(BuildContext context, {GameSession? session}) {
    probe(session!);
    return const Scaffold(body: Text('playing'));
  }
}

void main() {
  testWidgets('the session handed to a game outlives the lobby that made it', (
    tester,
  ) async {
    // Regression test for a bug that only bites on real hardware: the lobby
    // replaced its own route on hand-off, which disposed its controller, which
    // disposed the host — closing the very connection it had just given the
    // game. Every hosted match would have died the instant it started, and no
    // loopback test would have noticed, because none of them route through the
    // lobby and a mocked host closes nothing.
    final (hostLink, _) = LoopbackPeerConnection.pair(maxChunkBytes: 512);
    final host = _OwningFakeHost(hostLink);
    final scanner = _MockBleScanner();
    when(scanner.stopScan).thenAnswer((_) async {});

    GameSession? handedOff;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNearPlayTheme(),
        home: LobbyScreen(
          game: _ProbeGame((session) => handedOff = session),
          host: host,
          scanner: scanner,
          launcher: const _ImmediateLauncher(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Vedat');
    await tester.tap(find.text('Host a game'));
    await tester.pump();

    host.emitJoiner();
    // Not pumpAndSettle: the lobby shows an indeterminate spinner mid-connect,
    // which never settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(handedOff, isNotNull, reason: 'the game should have been opened');
    expect(find.text('playing'), findsOneWidget);
    expect(
      host.disposed,
      isFalse,
      reason: 'the host must keep serving the link it handed to the game',
    );
    expect(
      handedOff!.transport.state,
      PeerConnectionState.connected,
      reason: 'the game was handed a session that is still alive',
    );
    expect(
      hostLink.state,
      PeerConnectionState.connected,
      reason: 'the underlying link must not have been closed',
    );
  });
}
