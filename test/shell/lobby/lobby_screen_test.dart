import 'dart:async';

import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_host.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/shell/lobby/lobby_screen.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBleScanner extends Mock implements BleScanner {}

class _MockBleHost extends Mock implements BleHost {}

class _TestGame implements MiniGameDescriptor {
  const _TestGame();

  @override
  String get id => 'test';

  @override
  String get title => 'Test Game';

  @override
  bool get supportsMultiplayer => true;

  @override
  int get minPlayers => 2;

  @override
  int get maxPlayers => 2;

  @override
  Widget build(BuildContext context, {GameSession? session}) =>
      const Text('game started');
}

void main() {
  late _MockBleScanner scanner;
  late _MockBleHost host;

  setUpAll(() => registerFallbackValue(Duration.zero));

  setUp(() {
    scanner = _MockBleScanner();
    host = _MockBleHost();

    when(
      () => scanner.ensureReady(),
    ).thenAnswer((_) async => BleReadiness.ready);
    when(scanner.stopScan).thenAnswer((_) async {});
    when(
      () => scanner.scan(timeout: any(named: 'timeout')),
    ).thenAnswer((_) => const Stream<DiscoveredHost>.empty());

    when(() => host.ensureReady()).thenAnswer((_) async => BleReadiness.ready);
    when(() => host.startAdvertising(any())).thenAnswer((_) async {});
    when(host.stopAdvertising).thenAnswer((_) async {});
    when(host.stopAccepting).thenAnswer((_) async {});
    when(host.dispose).thenAnswer((_) async {});
    when(
      () => host.connections,
    ).thenAnswer((_) => const Stream<PeerConnection>.empty());
  });

  Future<void> pumpLobby(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: buildNearPlayTheme(),
      home: LobbyScreen(
        game: const _TestGame(),
        host: host,
        scanner: scanner,
      ),
    ),
  );

  testWidgets('offers both entrances and a name', (tester) async {
    await pumpLobby(tester);

    expect(find.text('Host a game'), findsOneWidget);
    expect(find.text('Join a game'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Test Game'), findsOneWidget);
  });

  testWidgets('hosting advertises the typed name', (tester) async {
    await pumpLobby(tester);

    await tester.enterText(find.byType(TextField), 'Vedat');
    await tester.tap(find.text('Host a game'));
    await tester.pump();

    verify(() => host.startAdvertising('Vedat')).called(1);
    expect(find.text('Waiting for a player'), findsOneWidget);
  });

  testWidgets('a discovered host is listed and tappable', (tester) async {
    final hosts = StreamController<DiscoveredHost>();
    when(
      () => scanner.scan(timeout: any(named: 'timeout')),
    ).thenAnswer((_) => hosts.stream);
    when(() => scanner.connect(any())).thenAnswer(
      (_) async => throw const BleException(JoinFailureReason.unknown),
    );

    await pumpLobby(tester);
    await tester.tap(find.text('Join a game'));
    await tester.pump();

    hosts.add(const DiscoveredHost(id: 'a', name: "Vedat's game", rssi: -40));
    await tester.pump();

    expect(find.text("Vedat's game"), findsOneWidget);
    // RSSI is rendered as a plain proximity cue, not a number.
    expect(find.text('Right here'), findsOneWidget);

    await hosts.close();
  });

  testWidgets('Bluetooth being off is explained, not swallowed', (
    tester,
  ) async {
    when(
      () => host.ensureReady(),
    ).thenAnswer((_) async => BleReadiness.poweredOff);

    await pumpLobby(tester);
    await tester.tap(find.text('Host a game'));
    await tester.pump();

    expect(find.textContaining('Bluetooth is off'), findsOneWidget);
  });

  testWidgets('an unsupported device gets no pointless retry button', (
    tester,
  ) async {
    when(
      () => host.ensureReady(),
    ).thenAnswer((_) async => BleReadiness.unsupported);

    await pumpLobby(tester);
    await tester.tap(find.text('Host a game'));
    await tester.pump();

    expect(find.textContaining("doesn't support Bluetooth"), findsOneWidget);
    expect(find.text('Back'), findsNothing);
  });
}
