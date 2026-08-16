import 'package:bluetooth_connected_gaming/core/transport/ble/ble_scanner.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart' as ble;

/// Translates the BLE package's adapter state into NearPlay's [BleReadiness].
///
/// Both radio adapters and the Bluetooth-off UI notice (#36) read the same
/// adapter state, so the mapping lives here rather than being repeated — a
/// divergence would mean the host and the joiner disagreed about whether the
/// radio was usable.
BleReadiness readinessFrom(ble.BluetoothLowEnergyState state) {
  return switch (state) {
    ble.BluetoothLowEnergyState.poweredOn => BleReadiness.ready,
    ble.BluetoothLowEnergyState.unauthorized => BleReadiness.unauthorized,
    ble.BluetoothLowEnergyState.unsupported => BleReadiness.unsupported,
    // `unknown` means the stack has not reported in yet. Treating it as
    // "off" is the safe read: the UI offers a retry, which is right whether
    // the adapter is genuinely off or merely slow to answer.
    ble.BluetoothLowEnergyState.poweredOff ||
    ble.BluetoothLowEnergyState.unknown => BleReadiness.poweredOff,
  };
}
