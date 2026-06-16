import 'package:flutter/foundation.dart' show immutable;

/// The authoritative position of one ball at a point in time.
///
/// Plain-Dart value type (no Flame/forge2d types) so a [PoolSnapshot] can later
/// be serialized into a `PeerMessage` `state` payload unchanged (see ADR-0008).
@immutable
class BallSnapshot {
  const BallSnapshot({
    required this.id,
    required this.x,
    required this.y,
    required this.pocketed,
  });

  /// Stable ball identifier (0 = cue ball).
  final int id;

  /// Position on the table, in simulation units.
  final double x;
  final double y;

  /// Whether the ball has been pocketed (removed from play).
  final bool pocketed;

  @override
  bool operator ==(Object other) =>
      other is BallSnapshot &&
      other.id == id &&
      other.x == x &&
      other.y == y &&
      other.pocketed == pocketed;

  @override
  int get hashCode => Object.hash(id, x, y, pocketed);

  @override
  String toString() =>
      'BallSnapshot(id: $id, x: $x, y: $y, pocketed: $pocketed)';
}

/// An immutable, authoritative snapshot of every ball on the table.
///
/// Produced by `PoolSimulation.step` and consumed by the renderer (and, later,
/// the transport). Carries no session/role state — it is just data.
@immutable
class PoolSnapshot {
  const PoolSnapshot({required this.balls});

  /// All balls, in a stable order (cue ball first).
  final List<BallSnapshot> balls;

  @override
  bool operator ==(Object other) {
    if (other is! PoolSnapshot) return false;
    if (other.balls.length != balls.length) return false;
    for (var i = 0; i < balls.length; i++) {
      if (other.balls[i] != balls[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(balls);

  @override
  String toString() => 'PoolSnapshot(balls: $balls)';
}
