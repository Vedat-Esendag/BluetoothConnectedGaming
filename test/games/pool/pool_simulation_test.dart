import 'package:bluetooth_connected_gaming/games/pool/pool_simulation.dart';
import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoolSimulation', () {
    test('racks 16 balls (cue + 15), none pocketed, cue ball id 0', () {
      final sim = PoolSimulation();
      final snap = sim.snapshot();

      expect(snap.balls.length, 16);
      expect(snap.balls.where((b) => b.pocketed), isEmpty);
      expect(snap.balls.first.id, 0);
    });

    test('striking the cue ball moves it along the aim direction', () {
      final sim = PoolSimulation();
      final startX = sim.snapshot().balls.first.x;

      // Strike along +x; check motion in the first few ticks, before the cue
      // ball can travel far enough to collide and rebound.
      sim.step(const [ShotCommand(angle: 0, power: 1)]);
      for (var i = 0; i < 10; i++) {
        sim.step();
      }

      expect(sim.snapshot().balls.first.x, greaterThan(startX));
    });

    test('comes to rest after a strike (damping works)', () {
      final sim = PoolSimulation()
        ..step(const [ShotCommand(angle: 0.3, power: 1)]);
      for (var i = 0; i < 1200; i++) {
        sim.step();
      }
      expect(sim.isAtRest, isTrue);
    });

    test('is deterministic: same commands produce identical snapshots', () {
      PoolSnapshotSeq run() {
        final sim = PoolSimulation();
        final frames = <String>[];
        sim.step(const [ShotCommand(angle: 0.7, power: 1)]);
        for (var i = 0; i < 300; i++) {
          frames.add(sim.step().toString());
        }
        return frames;
      }

      expect(run(), run());
    });
  });
}

typedef PoolSnapshotSeq = List<String>;
