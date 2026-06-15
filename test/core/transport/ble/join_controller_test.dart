import 'dart:async';

import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/core/transport/ble/join_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBleScanner extends Mock implements BleScanner {}

class _MockBleConnection extends Mock implements BleConnection {}

void main() {
  setUpAll(() => registerFallbackValue(Duration.zero));

  late _MockBleScanner scanner;
  late JoinController controller;

  const hostA = DiscoveredHost(id: 'a', name: 'Phone A', rssi: -40);
  const hostB = DiscoveredHost(id: 'b', name: 'Phone B', rssi: -55);

  setUp(() {
    scanner = _MockBleScanner();
    controller = JoinController(scanner);
    when(() => scanner.stopScan()).thenAnswer((_) async {});
  });

  tearDown(() => controller.dispose());

  void stubReady(BleReadiness readiness) =>
      when(() => scanner.ensureReady()).thenAnswer((_) async => readiness);

  void stubScan(Stream<DiscoveredHost> stream) => when(
    () => scanner.scan(timeout: any(named: 'timeout')),
  ).thenAnswer((_) => stream);

  JoinFailureReason failureReason() => (controller.state as JoinFailed).reason;

  group('readiness gate', () {
    test('unsupported -> bluetoothUnsupported and never scans', () async {
      stubReady(BleReadiness.unsupported);

      await controller.startScan();

      expect(controller.state, isA<JoinFailed>());
      expect(failureReason(), JoinFailureReason.bluetoothUnsupported);
      verifyNever(() => scanner.scan(timeout: any(named: 'timeout')));
    });

    test('poweredOff -> bluetoothOff', () async {
      stubReady(BleReadiness.poweredOff);

      await controller.startScan();

      expect(failureReason(), JoinFailureReason.bluetoothOff);
    });

    test('unauthorized -> permissionDenied', () async {
      stubReady(BleReadiness.unauthorized);

      await controller.startScan();

      expect(failureReason(), JoinFailureReason.permissionDenied);
    });
  });

  group('scanning', () {
    test('emits discovered hosts, deduplicated by id', () async {
      stubReady(BleReadiness.ready);
      stubScan(Stream<DiscoveredHost>.fromIterable([hostA, hostB, hostA]));

      await controller.startScan();
      await pumpEventQueue();

      expect(controller.state, isA<JoinFoundHosts>());
      final hosts = (controller.state as JoinFoundHosts).hosts;
      expect(hosts.map((h) => h.id), <String>['a', 'b']);
    });

    test('scan completes with no hosts -> noHostFound', () async {
      stubReady(BleReadiness.ready);
      stubScan(const Stream<DiscoveredHost>.empty());

      await controller.startScan();
      await pumpEventQueue();

      expect(failureReason(), JoinFailureReason.noHostFound);
    });

    test('scan error carrying a BleException -> its reason', () async {
      stubReady(BleReadiness.ready);
      stubScan(
        Stream<DiscoveredHost>.error(
          const BleException(JoinFailureReason.connectionRefused),
        ),
      );

      await controller.startScan();
      await pumpEventQueue();

      expect(failureReason(), JoinFailureReason.connectionRefused);
    });

    test('non-BleException scan error -> unknown', () async {
      stubReady(BleReadiness.ready);
      stubScan(Stream<DiscoveredHost>.error(Exception('boom')));

      await controller.startScan();
      await pumpEventQueue();

      expect(failureReason(), JoinFailureReason.unknown);
    });

    test('a second startScan while scanning is ignored', () async {
      stubReady(BleReadiness.ready);
      stubScan(const Stream<DiscoveredHost>.empty());

      await controller.startScan();
      await controller.startScan();

      verify(() => scanner.ensureReady()).called(1);
    });
  });

  group('connecting', () {
    test('success -> JoinConnected and stops scanning', () async {
      final connection = _MockBleConnection();
      when(() => scanner.connect(any())).thenAnswer((_) async => connection);

      await controller.connectToHost(hostA);

      expect(controller.state, isA<JoinConnected>());
      verify(() => scanner.stopScan()).called(1);
      verify(() => scanner.connect('a')).called(1);
    });

    test('a second connectToHost is ignored once connected', () async {
      final connection = _MockBleConnection();
      when(() => scanner.connect(any())).thenAnswer((_) async => connection);

      await controller.connectToHost(hostA);
      await controller.connectToHost(hostB);

      expect(controller.state, isA<JoinConnected>());
      verify(() => scanner.connect('a')).called(1);
      verifyNever(() => scanner.connect('b'));
    });

    test('BleException -> its reason', () async {
      when(() => scanner.connect(any())).thenThrow(
        const BleException(JoinFailureReason.characteristicDiscoveryFailed),
      );

      await controller.connectToHost(hostA);

      expect(failureReason(), JoinFailureReason.characteristicDiscoveryFailed);
    });

    test('unclassified error -> unknown', () async {
      when(() => scanner.connect(any())).thenThrow(Exception('boom'));

      await controller.connectToHost(hostA);

      expect(failureReason(), JoinFailureReason.unknown);
    });
  });

  test('dispose during an active scan cancels cleanly', () async {
    final scanStream = StreamController<DiscoveredHost>();
    stubReady(BleReadiness.ready);
    stubScan(scanStream.stream);
    final disposable = JoinController(scanner);

    await disposable.startScan();
    await pumpEventQueue();
    expect(disposable.state, isA<JoinScanning>());
    expect(disposable.dispose, returnsNormally);

    await scanStream.close();
  });

  test('notifies listeners on state change', () async {
    stubReady(BleReadiness.poweredOff);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.startScan();

    expect(notifications, greaterThan(0));
  });
}
