import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService {
  // Singleton design pattern
  BluetoothService._();
  static final BluetoothService instance = BluetoothService._();

  Future<void> initialise() async {

    // first, check if bluetooth is supported by your hardware
    // Note: The platform is initialized on the first call to any FlutterBluePlus method.
    if (!(await FlutterBluePlus.isSupported)) {
      //TODO: Send signal to UI: Display a signal informing the user the app is not compatible on their device
      print('Bluetooth not supported by this device');
      return;
    }

    // turn on bluetooth ourself if we can
    // for iOS, the user controls bluetooth enable/disable
    if (!kIsWeb && Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }

    return;
  }

}
