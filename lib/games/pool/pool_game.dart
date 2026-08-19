import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_simulation.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_snapshot.dart';
import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// Which side of a match this device is playing (ADR-0003).
enum PoolMode {
  /// One device, two players taking turns. This device simulates.
  local,

  /// Two devices; this one runs the authoritative simulation and broadcasts it.
  host,

  /// Two devices; this one renders what the host sends and sends shots back.
  /// It never steps physics — that is what keeps the two devices identical
  /// rather than merely similar.
  client,
}

/// The Flame render/loop layer for Pool.
///
/// Owns a [PoolSimulation] and a [PoolRulesEngine] and drives them at a fixed
/// timestep. Local play and hosting are the same code path; a **client** is the
/// exception — it steps nothing and simply renders the snapshots the host
/// sends, because two independent forge2d worlds would diverge on
/// floating-point rounding within a few seconds (ADR-0003, ADR-0008).
///
/// It knows nothing about the transport: a host publishes snapshots through
/// [onAuthoritativeState] and a client asks for shots through
/// [onShotRequested]. `PoolNetworkBinding` is what connects those to a
/// `GameSession`.
class PoolGame extends FlameGame {
  PoolGame({
    PoolSimulation? simulation,
    PoolRulesEngine? rules,
    this.mode = PoolMode.local,
  }) : _sim = simulation ?? PoolSimulation(),
       _rules = rules ?? PoolRulesEngine();

  /// Cap on physics catch-up per frame, so a long pause (e.g. backgrounding)
  /// doesn't trigger a huge burst of steps in a single update.
  static const int _maxCatchUpSteps = 8;

  /// Whether this device simulates, or renders what it is told.
  final PoolMode mode;

  /// Called on the host after every simulation step with the authoritative
  /// state to broadcast. Null for a local or client game.
  ValueChanged<PoolSnapshot>? onAuthoritativeState;

  /// Called on a client when the player takes a shot, so it can be sent to the
  /// host instead of applied locally. Null for a local or host game.
  ValueChanged<ShotCommand>? onShotRequested;

  /// Called on the host when the game is restarted, so the reset frame is sent
  /// even though the rules state may be identical to the one already
  /// broadcast.
  VoidCallback? onGameReset;

  PoolSimulation _sim;
  PoolRulesEngine _rules;

  /// The current rules/turn state, for the HUD to observe.
  final ValueNotifier<PoolGameState> stateNotifier = ValueNotifier(
    const PoolGameState(currentPlayer: PoolPlayer.one),
  );

  /// The latest snapshot, refreshed as the sim steps and read by the renderer —
  /// avoids allocating a new snapshot every render frame.
  late PoolSnapshot _lastSnapshot = _sim.snapshot();

  double _accumulator = 0;
  ShotCommand? _pendingShot;
  bool _settling = false;
  Set<int> _pocketedBeforeShot = const <int>{};

  /// The seat this device plays. The host is Player 1 (#13); in local play the
  /// one device plays both seats.
  PoolPlayer get localSeat =>
      mode == PoolMode.client ? PoolPlayer.two : PoolPlayer.one;

  /// Whether the local player may shoot right now: the table is at rest, the
  /// game is ongoing, and — in a two-device match — it is this player's turn.
  bool get canShoot {
    final state = gameState;
    if (_settling || state.isGameOver) return false;
    if (mode == PoolMode.local) return true;
    return state.currentPlayer == localSeat;
  }

  /// The current authoritative snapshot, for the host to broadcast.
  PoolSnapshot get snapshot => _lastSnapshot;

  /// The current rules state.
  ///
  /// A client has a rules engine but never advances it — the authority is the
  /// host (ADR-0003) — so its turn and winner come from the last state frame
  /// received, which is what [stateNotifier] holds.
  PoolGameState get gameState =>
      mode == PoolMode.client ? stateNotifier.value : _rules.state;

  /// Take a shot as the local player.
  ///
  /// On a client this does not touch the simulation — the shot is handed to
  /// [onShotRequested] and only becomes real when the host's next state frame
  /// says so. Ignored while the table is settling, the game is over, or it is
  /// the other player's turn.
  void shoot(ShotCommand command) {
    if (!canShoot) return;
    if (mode == PoolMode.client) {
      onShotRequested?.call(command);
      return;
    }
    _applyShot(command);
  }

  /// Apply a shot the client sent us. Host only.
  ///
  /// The host is the authority (ADR-0003), so it re-checks turn ownership here
  /// rather than trusting that the client asked at a legal moment: a client
  /// that shoots out of turn — buggy or hostile — is silently ignored.
  void applyRemoteShot(ShotCommand command) {
    if (mode != PoolMode.host) return;
    if (_settling || _rules.state.isGameOver) return;
    if (_rules.state.currentPlayer != PoolPlayer.two) return;
    _applyShot(command);
  }

  /// Adopt the host's authoritative state. Client only.
  void applyRemoteState(PoolSnapshot snapshot, PoolGameState gameState) {
    if (mode != PoolMode.client) return;
    _lastSnapshot = snapshot;
    // The host owns "is the table still moving": a client that guessed would
    // re-enable its own controls a frame early.
    _settling = false;
    if (stateNotifier.value != gameState) stateNotifier.value = gameState;
  }

  void _applyShot(ShotCommand command) {
    _pocketedBeforeShot = _pocketedIds(_lastSnapshot);
    // Contact tracking is per shot: what the cue ball hits first, and whether
    // anything reaches a cushion, decide legality and cannot be recovered once
    // the table is at rest.
    _sim.beginShot();
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
    _pocketedBeforeShot = const <int>{};
    _lastSnapshot = _sim.snapshot();
    stateNotifier.value = _rules.state;
    onGameReset?.call();
    _publish();
  }

  @override
  void update(double dt) {
    super.update(dt);
    // A client owns no simulation; its state arrives over the wire.
    if (mode == PoolMode.client) return;
    _accumulator += dt;
    const maxAccumulator = PoolSimulation.fixedDt * _maxCatchUpSteps;
    if (_accumulator > maxAccumulator) _accumulator = maxAccumulator;
    while (_accumulator >= PoolSimulation.fixedDt) {
      _advance();
      _accumulator -= PoolSimulation.fixedDt;
    }
  }

  void _advance() {
    final shot = _pendingShot;
    if (shot != null) {
      _pendingShot = null;
      _lastSnapshot = _sim.step(<ShotCommand>[shot]);
      _publish();
      return;
    }
    if (_settling) {
      _lastSnapshot = _sim.step();
      if (_sim.isAtRest) _resolveShot();
      _publish();
    }
  }

  void _publish() => onAuthoritativeState?.call(_lastSnapshot);

  void _resolveShot() {
    _settling = false;
    final after = _lastSnapshot;
    final pocketedNow = _pocketedIds(after).difference(_pocketedBeforeShot);
    final cuePocketed = after.balls.first.pocketed;
    _rules.applyShot(
      ShotOutcome(
        pocketed: pocketedNow,
        cuePocketed: cuePocketed,
        firstBallStruck: _sim.firstBallStruck,
        railContacted: _sim.railContacted,
      ),
    );
    if (cuePocketed && !_rules.state.isGameOver) {
      _sim.respawnCue();
      _lastSnapshot = _sim.snapshot(); // reflect the respawned cue ball
    }
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
    for (final ball in _lastSnapshot.balls) {
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
