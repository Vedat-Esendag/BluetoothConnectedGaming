import 'package:bluetooth_connected_gaming/games/pool/pool_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BallSnapshot', () {
    test('balls with identical fields are equal', () {
      expect(
        const BallSnapshot(id: 0, x: 1, y: 2, pocketed: false),
        const BallSnapshot(id: 0, x: 1, y: 2, pocketed: false),
      );
    });

    test('balls differing in any field are not equal', () {
      const base = BallSnapshot(id: 0, x: 1, y: 2, pocketed: false);
      expect(
        base,
        isNot(const BallSnapshot(id: 1, x: 1, y: 2, pocketed: false)),
      );
      expect(
        base,
        isNot(const BallSnapshot(id: 0, x: 9, y: 2, pocketed: false)),
      );
      expect(
        base,
        isNot(const BallSnapshot(id: 0, x: 1, y: 2, pocketed: true)),
      );
    });
  });

  group('PoolSnapshot', () {
    test('snapshots with the same balls in the same order are equal', () {
      PoolSnapshot make() => const PoolSnapshot(
        balls: [
          BallSnapshot(id: 0, x: 0, y: 0, pocketed: false),
          BallSnapshot(id: 1, x: 1.5, y: -2, pocketed: false),
        ],
      );
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('snapshots with a moved ball are not equal', () {
      const a = PoolSnapshot(
        balls: [BallSnapshot(id: 0, x: 0, y: 0, pocketed: false)],
      );
      const b = PoolSnapshot(
        balls: [BallSnapshot(id: 0, x: 0.01, y: 0, pocketed: false)],
      );
      expect(a, isNot(b));
    });
  });
}
