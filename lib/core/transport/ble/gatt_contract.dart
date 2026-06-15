/// The BLE GATT profile shared by the host (#7) and the joiner (#8).
///
/// Single source of truth for the service and characteristic UUIDs both sides
/// must agree on; see `docs/adr/0006-ble-gatt-profile.md`. Deliberately free of
/// any `flutter_blue_plus` import so non-adapter code — and tests — can depend
/// on it without pulling in the radio backend. The adapter converts these
/// strings to `Guid`s at the edge.
abstract final class GattContract {
  /// NearPlay session service the host advertises and the joiner scans for.
  static const String serviceUuid = 'e6695a2e-ec70-42b7-b660-84c1a06435df';

  /// Host -> joiner, `notify`: authoritative `state` frames (ADR-0003).
  static const String stateCharacteristicUuid =
      '0beeb145-5630-4c16-aa74-e62518406b28';

  /// Joiner -> host, `write`: `input` frames.
  static const String inputCharacteristicUuid =
      '9cca3888-905a-4a67-bc4b-b1e19af17f8c';
}
