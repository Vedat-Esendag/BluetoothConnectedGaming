import 'package:bluetooth_connected_gaming/core/transport/ble/gatt_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GattContract', () {
    // Canonical 128-bit UUID shape, lowercase hex. Guards against a typo or an
    // accidental edit that would silently break host/joiner interop (#7/#8).
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );

    final uuids = <String, String>{
      'serviceUuid': GattContract.serviceUuid,
      'stateCharacteristicUuid': GattContract.stateCharacteristicUuid,
      'inputCharacteristicUuid': GattContract.inputCharacteristicUuid,
    };

    for (final entry in uuids.entries) {
      test('${entry.key} is a well-formed lowercase 128-bit UUID', () {
        expect(
          uuidPattern.hasMatch(entry.value),
          isTrue,
          reason: '${entry.key} = ${entry.value}',
        );
      });
    }

    test('all three UUIDs are distinct', () {
      expect(uuids.values.toSet(), hasLength(uuids.length));
    });
  });
}
