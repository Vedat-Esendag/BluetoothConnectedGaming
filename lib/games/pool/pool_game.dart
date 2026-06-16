import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_simulation.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_snapshot.dart';
import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// The Flame render/loop layer for Pool.
///
/// Owns a [PoolSimulation] and a [PoolRulesEngine] and drives them at a fixed
/// timestep, but holds no transport/session state — local and (future)
/// multiplayer differ only in where snapshots come from (ADR-0008). It renders
/// the latest [PoolSnapshot]; turn/winner changes are published via
/// [stateNotifier] for the Flutter HUD.
class PoolGame extends FlameGame {
  PoolGame({PoolSimulation? simulation, PoolRulesEngine? rules})
    : _sim = simulation ?? PoolSimulation(),
      _rules = rules ?? PoolRulesEngine();

  static const double _fixedDt = 1 / 60;

  PoolSimulation _sim;
  PoolRulesEngine _rules;

  /// The current rules/turn state, for the HUD to observe.
  final ValueNotifier<PoolGameState> stateNotifier = ValueNotifier(
    const PoolGameState(currentPlayer: PoolPlayer.one),
  );

  double _accumulator = 0;
  ShotCommand? _pendingShot;
  bool _settling = false;
  Set<int> _pocketedBeforeShot = const <int>{};

  /// Whether a shot may be taken right now (table at rest, game ongoing).
  bool get canShoot => !_settling && !_rules.state.isGameOver;

  /// Queue a shot. Ignored while the table is still settling or the game is over.
  void shoot(ShotCommand command) {
    if (!canShoot) return;
    _pocketedBeforeShot = _pocketedIds(_sim.snapshot());
    _pendingShot = command;
    _settling = true;
  }

  /// Start a fresh game (the rematch action).
  void resetGame() {
    _sim = PoolSimulation();
    _rules = PoolRulesEngine();
    _settling = false;
    _pendingShot = null;
    _accumulator = 0;
    stateNotifier.value = _rules.state;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _accumulator += dt;
    while (_accumulator >= _fixedDt) {
      _advance();
      _accumulator -= _fixedDt;
    }
  }

  void _advance() {
    final shot = _pendingShot;
    if (shot != null) {
      _pendingShot = null;
      _sim.step(<ShotCommand>[shot]);
      return;
    }
    if (_settling) {
      _sim.step();
      if (_sim.isAtRest) _resolveShot();
    }
  }

  void _resolveShot() {
    _settling = false;
    final after = _sim.snapshot();
    final pocketedNow = _pocketedIds(after).difference(_pocketedBeforeShot);
    final cuePocketed = after.balls.first.pocketed;
    _rules.applyShot(pocketed: pocketedNow, cuePocketed: cuePocketed);
    if (cuePocketed && !_rules.state.isGameOver) _sim.respawnCue();
    stateNotifier.value = _rules.state;
  }

  Set<int> _pocketedIds(PoolSnapshot snap) => <int>{
    for (final ball in snap.balls)
      if (ball.pocketed) ball.id,
  };

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final scale = _scale();
    final origin = Offset(size.x / 2, size.y / 2);
    _paintTable(canvas, origin, scale);
    _paintBalls(canvas, origin, scale);
  }

  double _scale() {
    const margin = 24.0;
    final sx = (size.x - margin) / (2 * PoolSimulation.halfWidth);
    final sy = (size.y - margin) / (2 * PoolSimulation.halfHeight);
    return sx < sy ? sx : sy;
  }

  Offset _toScreen(double x, double y, Offset origin, double scale) =>
      Offset(origin.dx + x * scale, origin.dy - y * scale);

  void _paintTable(Canvas canvas, Offset origin, double scale) {
    final topLeft = _toScreen(
      -PoolSimulation.halfWidth,
      PoolSimulation.halfHeight,
      origin,
      scale,
    );
    final bottomRight = _toScreen(
      PoolSimulation.halfWidth,
      -PoolSimulation.halfHeight,
      origin,
      scale,
    );
    canvas.drawRect(
      Rect.fromPoints(topLeft, bottomRight),
      Paint()..color = const Color(0xFF14552B),
    );
    final pocketPaint = Paint()..color = const Color(0xFF06210F);
    for (final pocket in PoolSimulation.pocketCenters) {
      canvas.drawCircle(
        _toScreen(pocket.$1, pocket.$2, origin, scale),
        PoolSimulation.pocketRadius * scale,
        pocketPaint,
      );
    }
  }

  void _paintBalls(Canvas canvas, Offset origin, double scale) {
    for (final ball in _sim.snapshot().balls) {
      if (ball.pocketed) continue;
      canvas.drawCircle(
        _toScreen(ball.x, ball.y, origin, scale),
        PoolSimulation.ballRadius * scale,
        Paint()..color = _ballColor(ball.id),
      );
    }
  }

  Color _ballColor(int id) {
    if (id == 0) return Colors.white;
    if (id == PoolRulesEngine.eightBall) return Colors.black;
    return id.isEven ? Colors.amber : Colors.redAccent;
  }
}
