import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/session/handshake.dart';
import 'package:bluetooth_connected_gaming/core/session/session_launcher.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_host.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/shell/lobby/lobby_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/loopback_peer_connection.dart';

class _MockBleScanner extends Mock implements BleScanner {}

class _MockBleHost extends Mock implements BleHost {}

/// A launcher that never touches a transport, so lobby tests are about the
/// flow rather than about the handshake (which has its own tests).
class _FakeLauncher implements SessionLauncher {
  _FakeLauncher({this.failure});

  final HandshakeFailure? failure;
  PeerRole? launchedAs;

  @override
  Future<GameSession> launch({
    required PeerConnection connection,
    required PeerRole role,
    required String localName,
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) async {
    launchedAs = role;
    final reason = failure;
    if (reason != null) throw HandshakeException(reason);
    return GameSession(
      transport: _NullTransport(),
      role: role,
      localPlayerId: 'local-1',
      localPlayerName: localName,
      remotePlayerName: 'Peer',
    );
  }
}

class _NullTransport implements PeerTransport {
  @override
  Stream<PeerConnectionState> get connectionState =>
      const Stream<PeerConnectionState>.empty();

  @override
  Future<void> disconnect() async {}

  @override
  Stream<PeerMessage> get incoming => const Stream<PeerMessage>.empty();

  @override
  String get localPeerId => 'local-1';

  @override
  Future<void> send(MessageType type, Map<String, Object?> payload) async {}

  @override
  PeerConnectionState get state => PeerConnectionState.connected;
}

void main() {
  late _MockBleScanner scanner;
  late _MockBleHost host;
  late StreamController<PeerConnection> hostConnections;

  setUpAll(() => registerFallbackValue(Duration.zero));

  setUp(() {
    scanner = _MockBleScanner();
    host = _MockBleHost();
    hostConnections = StreamController<PeerConnection>.broadcast();

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
    when(() => host.connections).thenAnswer((_) => hostConnections.stream);
  });

  tearDown(() => hostConnections.close());

  LobbyController build({SessionLauncher? launcher}) => LobbyController(
    host: host,
    scanner: scanner,
    launcher: launcher ?? _FakeLauncher(),
  );

  group('readiness gate', () {
    for (final (readiness, fragment) in <(BleReadiness, String)>[
      (BleReadiness.poweredOff, 'Bluetooth is off'),
      (BleReadiness.unauthorized, 'permission'),
      (BleReadiness.unsupported, "doesn't support Bluetooth"),
    ]) {
      test('hosting on a ${readiness.name} adapter explains why', () async {
        when(() => host.ensureReady()).thenAnswer((_) async => readiness);
        final controller = build();

        await controller.startHosting('Vedat');

        expect(controller.state, isA<LobbyFailed>());
        expect((controller.state as LobbyFailed).message, contains(fragment));
        verifyNever(() => host.startAdvertising(any()));
      });

      test('scanning on a ${readiness.name} adapter explains why', () async {
        when(() => scanner.ensureReady()).thenAnswer((_) async => readiness);
        final controller = build();

        await controller.startScanning();

        expect(controller.state, isA<LobbyFailed>());
        verifyNever(() => scanner.scan(timeout: any(named: 'timeout')));
      });
    }

    test('an unsupported device is offered no retry', () async {
      when(
        () => host.ensureReady(),
      ).thenAnswer((_) async => BleReadiness.unsupported);
      final controller = build();

      await controller.startHosting('Vedat');

      expect((controller.state as LobbyFailed).canRetry, isFalse);
    });
  });

  group('hosting', () {
    test('advertises under the given name', () async {
      final controller = build();

      await controller.startHosting('Vedat');

      expect(controller.state, isA<LobbyHosting>());
      expect((controller.state as LobbyHosting).displayName, 'Vedat');
      verify(() => host.startAdvertising('Vedat')).called(1);
    });

    test('sanitizes the name it advertises', () async {
      final controller = build();

      await controller.startHosting('   ');

      verify(() => host.startAdvertising('Player')).called(1);
    });

    test('a joiner arriving launches the session as host', () async {
      final launcher = _FakeLauncher();
      final controller = build(launcher: launcher);
      await controller.startHosting('Vedat');

      final (connection, _) = LoopbackPeerConnection.pair();
      hostConnections.add(connection);
      await pumpEventQueue();

      expect(controller.state, isA<LobbyReady>());
      expect(launcher.launchedAs, PeerRole.host);
      // Withdrawing the service, not just the advertisement, is what stops a
      // second device joining a session that has already started.
      verify(host.stopAccepting).called(1);
    });

    test('a failed handshake surfaces as a readable message', () async {
      final controller = build(
        launcher: _FakeLauncher(failure: HandshakeFailure.roleConflict),
      );
      await controller.startHosting('Vedat');

      final (connection, _) = LoopbackPeerConnection.pair();
      hostConnections.add(connection);
      await pumpEventQueue();

      expect(controller.state, isA<LobbyFailed>());
      expect(
        (controller.state as LobbyFailed).message,
        contains('You both tapped Host'),
      );
    });

    test('advertising that the platform refuses is explained', () async {
      when(() => host.startAdvertising(any())).thenThrow(
        const BleHostException(HostFailureReason.advertisingFailed),
      );
      final controller = build();

      await controller.startHosting('Vedat');

      expect(
        (controller.state as LobbyFailed).message,
        contains("can't advertise"),
      );
    });

    test('a second startHosting while hosting is ignored', () async {
      final controller = build();

      await controller.startHosting('Vedat');
      await controller.startHosting('Vedat');

      verify(() => host.startAdvertising(any())).called(1);
    });
  });

  group('joining', () {
    test('discovered hosts are listed, deduplicated by id', () async {
      when(() => scanner.scan(timeout: any(named: 'timeout'))).thenAnswer(
        (_) => Stream<DiscoveredHost>.fromIterable(<DiscoveredHost>[
          const DiscoveredHost(id: 'a', name: 'Vedat', rssi: -40),
          const DiscoveredHost(id: 'a', name: 'Vedat', rssi: -50),
          const DiscoveredHost(id: 'b', name: 'Sam', rssi: -60),
        ]),
      );
      final controller = build();

      await controller.startScanning();
      await pumpEventQueue();

      final state = controller.state as LobbyScanning;
      expect(state.hosts.map((h) => h.id), <String>['a', 'b']);
      expect(state.hosts.first.rssi, -50, reason: 'the latest reading wins');
    });

    test('a scan that finds nothing says so', () async {
      final controller = build();

      await controller.startScanning();
      await pumpEventQueue();

      expect(
        (controller.state as LobbyFailed).message,
        contains('No game found nearby'),
      );
    });

    test('a scan error is mapped to its reason', () async {
      when(() => scanner.scan(timeout: any(named: 'timeout'))).thenAnswer(
        (_) => Stream<DiscoveredHost>.error(
          const BleException(JoinFailureReason.permissionDenied),
        ),
      );
      final controller = build();

      await controller.startScanning();
      await pumpEventQueue();

      expect(
        (controller.state as LobbyFailed).message,
        contains('permission'),
      );
    });

    test('joining a host launches the session as client', () async {
      final (connection, _) = LoopbackPeerConnection.pair();
      when(() => scanner.connect('a')).thenAnswer((_) async => connection);
      final launcher = _FakeLauncher();
      final controller = build(launcher: launcher);

      await controller.join(
        const DiscoveredHost(id: 'a', name: 'Vedat', rssi: -40),
        'Sam',
      );

      expect(controller.state, isA<LobbyReady>());
      expect(launcher.launchedAs, PeerRole.client);
      verify(scanner.stopScan).called(greaterThanOrEqualTo(1));
    });

    test('a refused connection is explained', () async {
      when(() => scanner.connect('a')).thenThrow(
        const BleException(JoinFailureReason.connectionRefused),
      );
      final controller = build();

      await controller.join(
        const DiscoveredHost(id: 'a', name: 'Vedat', rssi: -40),
        'Sam',
      );

      expect(
        (controller.state as LobbyFailed).message,
        contains('Could not connect'),
      );
    });

    test('a device that is not a NearPlay host is explained', () async {
      when(() => scanner.connect('a')).thenThrow(
        const BleException(JoinFailureReason.characteristicDiscoveryFailed),
      );
      final controller = build();

      await controller.join(
        const DiscoveredHost(id: 'a', name: 'Whatever', rssi: -40),
        'Sam',
      );

      expect(
        (controller.state as LobbyFailed).message,
        contains("isn't hosting NearPlay"),
      );
    });
  });

  group('lifecycle', () {
    test('cancel returns to the initial choice and stops the radio', () async {
      final controller = build();
      await controller.startHosting('Vedat');

      await controller.cancel();

      expect(controller.state, isA<LobbyIdle>());
      verify(host.stopAdvertising).called(greaterThanOrEqualTo(1));
      verify(scanner.stopScan).called(greaterThanOrEqualTo(1));
    });

    test('notifies listeners on every state change', () async {
      final controller = build();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.startHosting('Vedat');

      expect(notifications, greaterThan(0));
    });

    test('dispose releases both radios', () async {
      build().dispose();
      await pumpEventQueue();

      verify(host.dispose).called(1);
      verify(scanner.stopScan).called(greaterThanOrEqualTo(1));
    });
  });
}
