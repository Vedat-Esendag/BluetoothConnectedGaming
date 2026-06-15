import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_connected_gaming/shell/join/join_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBleScanner extends Mock implements BleScanner {}

void main() {
  setUpAll(() => registerFallbackValue(Duration.zero));

  late _MockBleScanner scanner;

  setUp(() {
    scanner = _MockBleScanner();
    when(() => scanner.stopScan()).thenAnswer((_) async {});
  });

  Future<void> pumpScreen(WidgetTester tester) =>
      tester.pumpWidget(MaterialApp(home: JoinScreen(scanner: scanner)));

  testWidgets('idle shows a scan prompt', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Scan for a host'), findsOneWidget);
  });

  testWidgets('powered-off Bluetooth shows an actionable failure', (
    tester,
  ) async {
    when(
      () => scanner.ensureReady(),
    ).thenAnswer((_) async => BleReadiness.poweredOff);
    await pumpScreen(tester);

    await tester.tap(find.text('Scan for a host'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bluetooth is off'), findsOneWidget);
    expect(find.text('Turn on Bluetooth'), findsOneWidget);
  });

  testWidgets('discovered hosts are listed by name', (tester) async {
    when(
      () => scanner.ensureReady(),
    ).thenAnswer((_) async => BleReadiness.ready);
    when(() => scanner.scan(timeout: any(named: 'timeout'))).thenAnswer(
      (_) => Stream<DiscoveredHost>.fromIterable(
        const [DiscoveredHost(id: 'a', name: 'Phone A', rssi: -40)],
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.text('Scan for a host'));
    await tester.pumpAndSettle();

    expect(find.text('Phone A'), findsOneWidget);
  });

  testWidgets('an empty scan shows the no-host recovery', (tester) async {
    when(
      () => scanner.ensureReady(),
    ).thenAnswer((_) async => BleReadiness.ready);
    when(
      () => scanner.scan(timeout: any(named: 'timeout')),
    ).thenAnswer((_) => const Stream<DiscoveredHost>.empty());
    await pumpScreen(tester);

    await tester.tap(find.text('Scan for a host'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No host found'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
  });
}
