import 'dart:math' as math;

import 'package:bluetooth_connected_gaming/games/pool/pool_snapshot.dart';
import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:forge2d/forge2d.dart';

/// The headless, deterministic Pool physics core (ADR-0008).
///
/// Owns a top-down (gravity-free) forge2d world: a cue ball, fifteen object
/// balls, four rails and six pockets. [step] advances one fixed timestep and
/// returns an authoritative [PoolSnapshot]. It imports `forge2d` only — never
/// Flame — and is **role-agnostic**: it knows nothing of `GameSession`, host vs
/// client, or the transport. The caller drives it.
class PoolSimulation {
  PoolSimulation() {
    _rackBalls();
    _buildRails();
  }

  /// Half the playing-surface width; valid x spans `[-halfWidth, halfWidth]`.
  static const double halfWidth = 10;

  /// Half the playing-surface height; valid y spans `[-halfHeight, halfHeight]`.
  static const double halfHeight = 5;
  static const double ballRadius = 0.5;
  static const double pocketRadius = 0.9;
  static const int ballCount = 16;

  static const double _fixedDt = 1 / 60;
  static const double _restSpeed = 0.05;
  static const double _maxImpulse = 30;
  static const double _railThickness = 1;

  final World _world = World(Vector2.zero());
  final List<_Ball> _balls = <_Ball>[];

  static final List<Vector2> _pockets = <Vector2>[
    Vector2(-halfWidth, -halfHeight),
    Vector2(halfWidth, -halfHeight),
    Vector2(-halfWidth, halfHeight),
    Vector2(halfWidth, halfHeight),
    Vector2(0, -halfHeight),
    Vector2(0, halfHeight),
  ];

  /// Advances the world by one fixed step, applying any [commands] first, and
  /// returns the resulting snapshot. Pure function of (current state, commands).
  PoolSnapshot step([List<ShotCommand> commands = const <ShotCommand>[]]) {
    commands.forEach(_applyShot);
    _world.stepDt(_fixedDt);
    _pocketBalls();
    return snapshot();
  }

  /// The current authoritative state of every ball.
  PoolSnapshot snapshot() => PoolSnapshot(
    balls: <BallSnapshot>[
      for (final ball in _balls)
        BallSnapshot(
          id: ball.id,
          x: ball.pocketed ? 0 : ball.body.position.x,
          y: ball.pocketed ? 0 : ball.body.position.y,
          pocketed: ball.pocketed,
        ),
    ],
  );

  /// Whether every ball in play has effectively stopped moving.
  bool get isAtRest => _balls.every(
    (ball) => ball.pocketed || ball.body.linearVelocity.length < _restSpeed,
  );

  /// Pocket centres as plain `(x, y)` records (no forge2d types leak out, per
  /// ADR-0008) — for the renderer to draw the pockets.
  static List<(double, double)> get pocketCenters => <(double, double)>[
    for (final pocket in _pockets) (pocket.x, pocket.y),
  ];

  void _applyShot(ShotCommand command) {
    final cue = _balls.first;
    if (cue.pocketed) return;
    final magnitude = command.power.clamp(0.0, 1.0) * _maxImpulse;
    final impulse =
        Vector2(math.cos(command.angle), math.sin(command.angle)) * magnitude;
    cue.body.applyLinearImpulse(impulse);
  }

  void _pocketBalls() {
    for (final ball in _balls) {
      if (ball.pocketed) continue;
      final position = ball.body.position;
      for (final pocket in _pockets) {
        if (position.distanceTo(pocket) < pocketRadius) {
          ball.pocketed = true;
          _world.destroyBody(ball.body);
          break;
        }
      }
    }
  }

  /// Re-spawns a scratched cue ball at the head spot so play can continue.
  /// No-op if the cue ball is already in play. (Ball-in-hand placement is v2.)
  void respawnCue() {
    final cue = _balls.first;
    if (!cue.pocketed) return;
    cue
      ..body = _createBallBody(_cueHeadSpot)
      ..pocketed = false;
  }

  Vector2 get _cueHeadSpot => Vector2(-halfWidth / 2, 0);

  void _rackBalls() {
    _addBall(0, _cueHeadSpot);
    const spacing = ballRadius * 2 + 0.02;
    const apexX = halfWidth / 2;
    var id = 1;
    for (var row = 0; row < 5; row++) {
      final x = apexX + row * spacing * 0.87; // cos(30°) row offset
      for (var i = 0; i <= row; i++) {
        final y = (i - row / 2) * spacing;
        _addBall(id++, Vector2(x, y));
      }
    }
  }

  void _addBall(int id, Vector2 position) {
    _balls.add(_Ball(id, _createBallBody(position)));
  }

  Body _createBallBody(Vector2 position) {
    return _world.createBody(
      BodyDef()
        ..type = BodyType.dynamic
        ..position = position
        ..linearDamping = 0.8
        ..angularDamping = 0.8
        ..bullet = true, // continuous collision: don't tunnel through rails
    )..createFixtureFromShape(
      CircleShape()..radius = ballRadius,
      friction: 0.2,
      restitution: 0.92,
    );
  }

  void _buildRails() {
    const t = _railThickness;
    _addRail(Vector2(0, -halfHeight - t / 2), halfWidth + t, t / 2);
    _addRail(Vector2(0, halfHeight + t / 2), halfWidth + t, t / 2);
    _addRail(Vector2(-halfWidth - t / 2, 0), t / 2, halfHeight + t);
    _addRail(Vector2(halfWidth + t / 2, 0), t / 2, halfHeight + t);
  }

  void _addRail(Vector2 center, double halfW, double halfH) {
    _world
        .createBody(BodyDef()..position = center)
        .createFixtureFromShape(
          PolygonShape()..setAsBoxXY(halfW, halfH),
          friction: 0.2,
          restitution: 0.6,
        );
  }
}

class _Ball {
  _Ball(this.id, this.body);

  final int id;
  Body body;
  bool pocketed = false;
}
