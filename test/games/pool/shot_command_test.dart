import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShotCommand', () {
    test('two commands with the same angle and power are equal', () {
      expect(
        const ShotCommand(angle: 1.2, power: 0.5),
        const ShotCommand(angle: 1.2, power: 0.5),
      );
      expect(
        const ShotCommand(angle: 1.2, power: 0.5).hashCode,
        const ShotCommand(angle: 1.2, power: 0.5).hashCode,
      );
    });

    test('commands differing in angle or power are not equal', () {
      const base = ShotCommand(angle: 1, power: 0.5);
      expect(base, isNot(const ShotCommand(angle: 2, power: 0.5)));
      expect(base, isNot(const ShotCommand(angle: 1, power: 0.9)));
    });
  });
}
