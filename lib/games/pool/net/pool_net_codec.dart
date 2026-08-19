import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_simulation.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_snapshot.dart';
import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:flutter/foundation.dart' show immutable;

/// Wire keys for Pool's payloads. Short by design: every `state` frame carries
/// them, and a BLE link at the unnegotiated MTU moves ~20 bytes per packet.
abstract final class PoolWireKeys {
  /// Flat `[x0, y0, x1, y1, …]` ball positions, indexed by ball id.
  static const String positions = 'b';

  /// Bitmask of pocketed ball ids.
  static const String pocketed = 'p';

  /// Index of the player to shoot (0 = host, 1 = joiner).
  static const String turn = 't';

  /// Index of the winner, or absent while the game is ongoing.
  static const String winner = 'w';

  /// Shot aim, in radians.
  static const String angle = 'a';

  /// Shot power, 0..1.
  static const String power = 'q';
}

/// Number of balls on the table: the cue ball plus fifteen objects.
const int poolBallCount = 16;

/// Decimal places retained for a ball coordinate on the wire.
///
/// The table is 20 units across, so three decimals is well under a pixel at any
/// sane screen size and roughly halves the size of a `state` frame.
const int poolWirePrecision = 3;

/// A decoded, validated authoritative state frame.
@immutable
class PoolNetState {
  const PoolNetState({required this.snapshot, required this.gameState});

  /// Where every ball is.
  final PoolSnapshot snapshot;

  /// Whose turn it is, and whether anyone has won.
  final PoolGameState gameState;
}

/// Encode the host's authoritative state for broadcast (ADR-0003).
Map<String, Object?> encodePoolState(
  PoolSnapshot snapshot,
  PoolGameState gameState,
) {
  final positions = <double>[];
  var pocketed = 0;
  for (final ball in snapshot.balls) {
    positions
      ..add(_round(ball.x))
      ..add(_round(ball.y));
    if (ball.pocketed) pocketed |= 1 << ball.id;
  }

  return <String, Object?>{
    PoolWireKeys.positions: positions,
    PoolWireKeys.pocketed: pocketed,
    PoolWireKeys.turn: gameState.currentPlayer.index,
    if (gameState.winner != null) PoolWireKeys.winner: gameState.winner!.index,
  };
}

/// Decode a `state` payload, or return null if it is not one.
///
/// The payload has already passed `PeerMessage.fromWire`, which only proves it
/// is a well-formed JSON object — every value here is still the peer's to
/// choose. A client that trusted them would happily render balls at infinity or
/// off the table, so each one is range-checked and a single bad field rejects
/// the whole frame rather than being patched up.
PoolNetState? decodePoolState(Map<String, Object?> payload) {
  final rawPositions = payload[PoolWireKeys.positions];
  if (rawPositions is! List || rawPositions.length != poolBallCount * 2) {
    return null;
  }

  final coordinates = <double>[];
  for (final value in rawPositions) {
    final coordinate = _finiteDouble(value);
    if (coordinate == null) return null;
    coordinates.add(coordinate);
  }

  final pocketedMask = payload[PoolWireKeys.pocketed];
  // Only the low 16 bits can name a real ball.
  if (pocketedMask is! int ||
      pocketedMask < 0 ||
      pocketedMask >= (1 << poolBallCount)) {
    return null;
  }

  final turn = _playerAt(payload[PoolWireKeys.turn]);
  if (turn == null) return null;

  final PoolPlayer? winner;
  if (payload.containsKey(PoolWireKeys.winner)) {
    winner = _playerAt(payload[PoolWireKeys.winner]);
    if (winner == null) return null;
  } else {
    winner = null;
  }

  final balls = <BallSnapshot>[];
  for (var id = 0; id < poolBallCount; id++) {
    final pocketed = pocketedMask & (1 << id) != 0;
    final x = coordinates[id * 2];
    final y = coordinates[id * 2 + 1];
    // A ball in play must be somewhere on the table. The margin allows for a
    // ball mid-collision with a rail; anything beyond it is not a position the
    // host's simulation could have produced.
    if (!pocketed && !_onTable(x, y)) return null;
    balls.add(BallSnapshot(id: id, x: x, y: y, pocketed: pocketed));
  }

  return PoolNetState(
    snapshot: PoolSnapshot(balls: balls),
    gameState: PoolGameState(currentPlayer: turn, winner: winner),
  );
}

/// Encode a shot for the client to send to the host.
Map<String, Object?> encodeShot(ShotCommand shot) => <String, Object?>{
  PoolWireKeys.angle: _round(shot.angle),
  PoolWireKeys.power: _round(shot.power),
};

/// Decode an `input` payload, or return null if it is not a usable shot.
///
/// Power is clamped rather than rejected — a peer sending 1.4 is more likely a
/// rounding artefact than an attack — but a non-finite value is refused
/// outright, because it would propagate straight into the physics world as NaN
/// and corrupt the host's authoritative state for both players.
ShotCommand? decodeShot(Map<String, Object?> payload) {
  final angle = _finiteDouble(payload[PoolWireKeys.angle]);
  final power = _finiteDouble(payload[PoolWireKeys.power]);
  if (angle == null || power == null) return null;
  return ShotCommand(angle: angle, power: power.clamp(0.0, 1.0));
}

bool _onTable(double x, double y) {
  const margin = PoolSimulation.ballRadius * 2;
  return x.abs() <= PoolSimulation.halfWidth + margin &&
      y.abs() <= PoolSimulation.halfHeight + margin;
}

PoolPlayer? _playerAt(Object? value) {
  if (value is! int || value < 0 || value >= PoolPlayer.values.length) {
    return null;
  }
  return PoolPlayer.values[value];
}

/// JSON numbers decode as `int` or `double`; both are acceptable, NaN and
/// infinity are not.
double? _finiteDouble(Object? value) {
  if (value is! num) return null;
  final asDouble = value.toDouble();
  return asDouble.isFinite ? asDouble : null;
}

double _round(double value) {
  const factor = 1000; // 10^poolWirePrecision
  return (value * factor).roundToDouble() / factor;
}
