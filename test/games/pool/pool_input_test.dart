import 'dart:math' as math;

import 'package:bluetooth_connected_gaming/games/pool/pool_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shotFromDrag (slingshot aiming)', () {
    test('power is the drag length over the max, clamped to 0..1', () {
      expect(
        shotFromDrag(const Offset(50, 0), maxDragDistance: 100).power,
        closeTo(0.5, 1e-9),
      );
      expect(
        shotFromDrag(const Offset(500, 0), maxDragDistance: 100).power,
        1.0,
      );
    });

    test('dragging down the screen shoots up the table (+y in sim space)', () {
      final shot = shotFromDrag(const Offset(0, 80), maxDragDistance: 100);
      expect(shot.angle, closeTo(math.pi / 2, 1e-9));
    });

    test('dragging left shoots right (angle ~ 0)', () {
      final shot = shotFromDrag(const Offset(-80, 0), maxDragDistance: 100);
      expect(shot.angle, closeTo(0, 1e-9));
    });
  });
}
