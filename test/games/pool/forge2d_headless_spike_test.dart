// Day-one de-risk spike (plan step 0 / ADR-0008).
//
// Proves the load-bearing assumption of the whole local-first Pool plan: that
// `forge2d` can be driven in a pure-Dart test with NO `package:flame` import,
// and that stepping it is deterministic (same inputs -> identical output). If
// this is green, a headless `PoolSimulation` is viable and the determinism test
// ADR-0003 requires is achievable. The only physics import below is forge2d.
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart';

/// Drops a unit circle under gravity for [steps] fixed ticks and returns the
/// final y position. Pure function of its inputs — no shared state.
double _fallY({required int steps}) {
  final world = World(Vector2(0, -10));
  final body = world.createBody(
    BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(0, 100),
  )..createFixtureFromShape(CircleShape()..radius = 0.5);

  for (var i = 0; i < steps; i++) {
    world.stepDt(1 / 60);
  }
  return body.position.y;
}

void main() {
  group('forge2d headless spike', () {
    test('steps without Flutter/Flame and the body actually falls', () {
      final y = _fallY(steps: 60);
      expect(y, lessThan(100), reason: 'gravity should pull the body down');
    });

    test('is deterministic: identical inputs produce identical output', () {
      expect(_fallY(steps: 120), _fallY(steps: 120));
    });
  });
}
