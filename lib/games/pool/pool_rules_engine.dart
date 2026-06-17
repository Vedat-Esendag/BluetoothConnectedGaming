import 'package:flutter/foundation.dart' show immutable;

/// The two local (pass-and-play) players.
enum PoolPlayer {
  one,
  two;

  PoolPlayer get other => this == one ? two : one;
}

/// An immutable snapshot of the rules/turn state.
@immutable
class PoolGameState {
  const PoolGameState({required this.currentPlayer, this.winner});

  /// Whose turn it is to shoot.
  final PoolPlayer currentPlayer;

  /// The winner, or null while the game is ongoing.
  final PoolPlayer? winner;

  bool get isGameOver => winner != null;

  @override
  bool operator ==(Object other) =>
      other is PoolGameState &&
      other.currentPlayer == currentPlayer &&
      other.winner == winner;

  @override
  int get hashCode => Object.hash(currentPlayer, winner);

  @override
  String toString() =>
      'PoolGameState(currentPlayer: $currentPlayer, winner: $winner)';
}

/// Minimal 8-ball rules for local pass-and-play (ADR-0008).
///
/// Pure Dart, no Flame/forge2d dependency. The caller runs a shot to rest, then
/// reports which balls were pocketed; the engine advances the turn and decides
/// the winner. Solids/stripes group assignment, legal-first-contact and no-rail
/// fouls are deferred (v2) — this is the smallest complete loop.
class PoolRulesEngine {
  /// The id of the 8-ball.
  static const int eightBall = 8;

  /// The 14 non-cue, non-8 object balls.
  static final Set<int> _objectBalls = {
    for (var id = 1; id <= 15; id++)
      if (id != eightBall) id,
  };

  final Set<int> _pocketedObjectBalls = <int>{};
  PoolPlayer _currentPlayer = PoolPlayer.one;
  PoolPlayer? _winner;

  PoolGameState get state =>
      PoolGameState(currentPlayer: _currentPlayer, winner: _winner);

  /// Apply the outcome of one completed shot.
  ///
  /// [pocketed] is every ball id that dropped this shot (may include the
  /// 8-ball); [cuePocketed] is whether the cue ball scratched.
  void applyShot({required Set<int> pocketed, required bool cuePocketed}) {
    if (_winner != null) return;

    if (pocketed.contains(eightBall)) {
      _resolveEightBall(cuePocketed: cuePocketed);
      return;
    }

    final sankObjectBall = pocketed.any(_objectBalls.contains);
    _pocketedObjectBalls.addAll(pocketed.where(_objectBalls.contains));

    // A scratch is a foul (turn passes); otherwise the shooter keeps the table
    // only if they legally pocketed something.
    if (cuePocketed || !sankObjectBall) {
      _currentPlayer = _currentPlayer.other;
    }
  }

  void _resolveEightBall({required bool cuePocketed}) {
    final clearedTheRest = _objectBalls.every(_pocketedObjectBalls.contains);
    final legalWin = clearedTheRest && !cuePocketed;
    _winner = legalWin ? _currentPlayer : _currentPlayer.other;
  }
}
