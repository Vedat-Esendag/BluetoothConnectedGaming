import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_theme.dart';
import 'package:bluetooth_connected_gaming/shell/widgets/connection_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A transport whose link state the test drives directly.
class _FakeTransport implements PeerTransport {
  final StreamController<PeerConnectionState> _states =
      StreamController<PeerConnectionState>.broadcast();

  PeerConnectionState _state = PeerConnectionState.connected;
  bool disconnected = false;

  void drop() {
    _state = PeerConnectionState.disconnected;
    _states.add(_state);
  }

  Future<void> close() => _states.close();

  @override
  Stream<PeerConnectionState> get connectionState => _states.stream;

  @override
  Future<void> disconnect() async => disconnected = true;

  @override
  Stream<PeerMessage> get incoming => const Stream<PeerMessage>.empty();

  @override
  String get localPeerId => 'host-1';

  @override
  Future<void> send(MessageType type, Map<String, Object?> payload) async {}

  @override
  PeerConnectionState get state => _state;
}

void main() {
  late _FakeTransport transport;

  setUp(() => transport = _FakeTransport());
  tearDown(() => transport.close());

  Widget wrap(Widget child) => MaterialApp(
    theme: buildNearPlayTheme(),
    home: Scaffold(
      body: ConnectionOverlay(
        session: GameSession(
          transport: transport,
          role: PeerRole.host,
          localPlayerId: 'host-1',
          remotePlayerName: 'Sam',
        ),
        child: child,
      ),
    ),
  );

  testWidgets('shows the game while the peer is connected', (tester) async {
    await tester.pumpWidget(wrap(const Text('the board')));

    expect(find.text('the board'), findsOneWidget);
    expect(find.text('Connection lost'), findsNothing);
  });

  testWidgets('covers the game when the peer drops', (tester) async {
    await tester.pumpWidget(wrap(const Text('the board')));

    transport.drop();
    await tester.pump();

    expect(find.text('Connection lost'), findsOneWidget);
    // Named, so the player knows who left rather than reading a status code.
    expect(find.textContaining('Sam'), findsOneWidget);
    expect(find.text('Back to games'), findsOneWidget);
  });

  testWidgets('leaving tears the session down', (tester) async {
    await tester.pumpWidget(wrap(const Text('the board')));
    transport.drop();
    await tester.pump();

    await tester.tap(find.text('Back to games'));
    await tester.pumpAndSettle();

    expect(transport.disconnected, isTrue);
  });

  testWidgets('offers no reconnect, which the transport could not honour', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const Text('the board')));
    transport.drop();
    await tester.pump();

    expect(find.textContaining('Reconnect'), findsNothing);
  });
}
