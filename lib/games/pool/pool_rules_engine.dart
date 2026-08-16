import 'package:flutter/foundation.dart' show immutable;

/// The two players.
enum PoolPlayer {
  one,
  two;

  PoolPlayer get other => this == one ? two : one;
}

/// A player's assigned group of object balls.
enum BallGroup {
  /// Balls 1–7.
  solids,

  /// Balls 9–15.
  stripes;

  /// The ids belonging to this group.
  Set<int> get ids => this == solids
      ? const <int>{1, 2, 3, 4, 5, 6, 7}
      : const <int>{9, 10, 11, 12, 13, 14, 15};

  /// The other group.
  BallGroup get other => this == solids ? stripes : solids;
}

/// Why a shot was a foul, or null if it was legal.
enum PoolFoul {
  /// The cue ball was pocketed.
  scratch,

  /// The cue ball touched nothing.
  noContact,

  /// The cue ball struck a ball the shooter was not entitled to hit first.
  wrongBallFirst,

  /// Nothing was pocketed and no ball reached a cushion.
  noRail,
}

/// An immutable snapshot of the rules/turn state.
@immutable
class PoolGameState {
  const PoolGameState({
    required this.currentPlayer,
    this.winner,
    this.groups = const <PoolPlayer, BallGroup>{},
    this.lastFoul,
    this.ballInHand = false,
  });

  /// Whose turn it is to shoot.
  final PoolPlayer currentPlayer;

  /// The winner, or null while the game is ongoing.
  final PoolPlayer? winner;

  /// Each player's group, once the table is no longer open.
  final Map<PoolPlayer, BallGroup> groups;

  /// Why the previous shot was a foul, or null if it was legal.
  final PoolFoul? lastFoul;

  /// Whether the incoming player may place the cue ball (after a foul).
  final bool ballInHand;

  /// Whether groups have been assigned yet.
  bool get isTableOpen => groups.isEmpty;

  /// The group [player] is shooting, or null while the table is open.
  BallGroup? groupFor(PoolPlayer player) => groups[player];

  bool get isGameOver => winner != null;

  @override
  bool operator ==(Object other) =>
      other is PoolGameState &&
      other.currentPlayer == currentPlayer &&
      other.winner == winner &&
      other.lastFoul == lastFoul &&
      other.ballInHand == ballInHand &&
      _sameGroups(other.groups);

  bool _sameGroups(Map<PoolPlayer, BallGroup> other) {
    if (other.length != groups.length) return false;
    for (final entry in groups.entries) {
      if (other[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    currentPlayer,
    winner,
    lastFoul,
    ballInHand,
    groups[PoolPlayer.one],
    groups[PoolPlayer.two],
  );

  @override
  String toString() =>
      'PoolGameState(currentPlayer: $currentPlayer, winner: $winner, '
      'groups: $groups, lastFoul: $lastFoul, ballInHand: $ballInHand)';
}

/// What happened during one completed shot, as observed by the simulation.
@immutable
class ShotOutcome {
  const ShotOutcome({
    this.pocketed = const <int>{},
    this.cuePocketed = false,
    this.firstBallStruck,
    this.railContacted = true,
  });

  /// Every ball id that dropped this shot.
  final Set<int> pocketed;

  /// Whether the cue ball scratched.
  final bool cuePocketed;

  /// The first ball the cue ball touched, or null if it touched none.
  final int? firstBallStruck;

  /// Whether any ball reached a cushion.
  final bool railContacted;
}

/// 8-ball rules: group assignment, fouls, turn order, and the win condition
/// (#22).
///
/// Pure Dart with no Flame or forge2d dependency, so every rule is unit-tested
/// without a physics world. It is told what happened ([ShotOutcome]) and decides
/// what it means; it never inspects the table itself.
///
/// **Simplifications, deliberate and recorded:** ball-in-hand is reported as a
/// flag but the cue ball respawns at the head spot rather than being placed by
/// the player; the break is treated as an ordinary shot; and the 8-ball does not
/// have to be called to a pocket. Each is a UI or scope decision, not a missing
/// rule — see the Pool section of the CHANGELOG.
class PoolRulesEngine {
  /// The id of the 8-ball.
  static const int eightBall = 8;

  /// The id of the cue ball.
  static const int cueBall = 0;

  final Set<int> _pocketed = <int>{};
  final Map<PoolPlayer, BallGroup> _groups = <PoolPlayer, BallGroup>{};

  PoolPlayer _currentPlayer = PoolPlayer.one;
  PoolPlayer? _winner;
  PoolFoul? _lastFoul;
  bool _ballInHand = false;

  /// The current rules state.
  PoolGameState get state => PoolGameState(
    currentPlayer: _currentPlayer,
    winner: _winner,
    groups: Map<PoolPlayer, BallGroup>.unmodifiable(_groups),
    lastFoul: _lastFoul,
    ballInHand: _ballInHand,
  );

  /// Every object ball pocketed so far.
  Set<int> get pocketedBalls => Set<int>.unmodifiable(_pocketed);

  /// Whether [player] has cleared their group and may shoot the 8-ball.
  bool isOnTheEightBall(PoolPlayer player) {
    final group = _groups[player];
    if (group == null) return false;
    return group.ids.every(_pocketed.contains);
  }

  /// Apply the outcome of one completed shot.
  void applyShot(ShotOutcome outcome) {
    if (_winner != null) return;

    // Everything is judged against the table as it was *before* this shot.
    // Scoring the balls first would mean the shot that pots the last ball of
    // your group is judged as if you were already on the 8-ball — so a
    // perfectly legal clearance would read as hitting the wrong ball first.
    final wasOnEightBall = isOnTheEightBall(_currentPlayer);

    // The 8-ball ends the game either way — legally if the shooter had already
    // cleared their group and did not scratch, otherwise as a loss. Potting the
    // last group ball and the 8-ball in one shot is a loss: the group was not
    // clear when the 8 went down.
    if (outcome.pocketed.contains(eightBall)) {
      _resolveEightBall(
        clearedGroup: wasOnEightBall,
        cuePocketed: outcome.cuePocketed,
      );
      return;
    }

    final foul = _foulFor(outcome, onEightBall: wasOnEightBall);
    _pocketed.addAll(outcome.pocketed.where((id) => id != cueBall));
    if (foul == null) _assignGroups(outcome);

    final keepsTable = foul == null && _pocketedOwnGroup(outcome);
    _lastFoul = foul;
    _ballInHand = foul != null;
    if (!keepsTable) _currentPlayer = _currentPlayer.other;
  }

  /// Which foul, if any, this shot committed.
  ///
  /// [onEightBall] is whether the shooter had cleared their group *before* this
  /// shot, which is what makes the 8-ball a legal first contact.
  PoolFoul? _foulFor(ShotOutcome outcome, {required bool onEightBall}) {
    if (outcome.cuePocketed) return PoolFoul.scratch;

    final struck = outcome.firstBallStruck;
    if (struck == null) return PoolFoul.noContact;

    final group = _groups[_currentPlayer];
    if (group == null) {
      // On an open table any object ball is a legal first contact — except the
      // 8-ball, which is never legal to hit first before groups are assigned.
      if (struck == eightBall) return PoolFoul.wrongBallFirst;
    } else {
      // Once you have a group you must hit it first — unless you are on the
      // 8-ball, in which case the 8-ball is your legal first contact.
      final legalFirst = onEightBall ? <int>{eightBall} : group.ids;
      if (!legalFirst.contains(struck)) return PoolFoul.wrongBallFirst;
    }

    // Hitting the right ball and then letting everything die mid-table is
    // still a foul: something must be pocketed or reach a cushion.
    if (outcome.pocketed.isEmpty && !outcome.railContacted) {
      return PoolFoul.noRail;
    }
    return null;
  }

  /// Claim groups on the first legal pot on an open table.
  ///
  /// If the shot dropped balls from both groups the table stays open — there is
  /// no basis for choosing, and guessing would hand someone a group they never
  /// earned.
  void _assignGroups(ShotOutcome outcome) {
    if (_groups.isNotEmpty) return;

    final solids = outcome.pocketed.where(BallGroup.solids.ids.contains).length;
    final stripes = outcome.pocketed
        .where(BallGroup.stripes.ids.contains)
        .length;
    if (solids == 0 && stripes == 0) return;
    if (solids > 0 && stripes > 0) return;

    final claimed = solids > 0 ? BallGroup.solids : BallGroup.stripes;
    _groups[_currentPlayer] = claimed;
    _groups[_currentPlayer.other] = claimed.other;
  }

  /// Whether the shooter pocketed a ball that entitles them to shoot again.
  bool _pocketedOwnGroup(ShotOutcome outcome) {
    final group = _groups[_currentPlayer];
    if (group == null) {
      // Table was open: any object ball keeps the table.
      return outcome.pocketed.any((id) => id != cueBall && id != eightBall);
    }
    return outcome.pocketed.any(group.ids.contains);
  }

  void _resolveEightBall({
    required bool clearedGroup,
    required bool cuePocketed,
  }) {
    final legal = clearedGroup && !cuePocketed;
    _winner = legal ? _currentPlayer : _currentPlayer.other;
    _lastFoul = cuePocketed ? PoolFoul.scratch : null;
    _ballInHand = false;
  }
}
