import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// A legal-looking shot by default, so each test only states what it is about.
ShotOutcome shot({
  Set<int> pocketed = const <int>{},
  bool cuePocketed = false,
  int? firstBallStruck = 1,
  bool railContacted = true,
}) => ShotOutcome(
  pocketed: pocketed,
  cuePocketed: cuePocketed,
  firstBallStruck: firstBallStruck,
  railContacted: railContacted,
);

void main() {
  late PoolRulesEngine rules;

  setUp(() => rules = PoolRulesEngine());

  group('opening state', () {
    test('player one shoots at an open table', () {
      expect(rules.state.currentPlayer, PoolPlayer.one);
      expect(rules.state.isTableOpen, isTrue);
      expect(rules.state.winner, isNull);
      expect(rules.state.ballInHand, isFalse);
    });
  });

  group('group assignment', () {
    test('potting a solid claims solids for the shooter', () {
      rules.applyShot(shot(pocketed: <int>{3}));

      expect(rules.state.groupFor(PoolPlayer.one), BallGroup.solids);
      expect(rules.state.groupFor(PoolPlayer.two), BallGroup.stripes);
    });

    test('potting a stripe claims stripes for the shooter', () {
      rules.applyShot(shot(pocketed: <int>{11}, firstBallStruck: 11));

      expect(rules.state.groupFor(PoolPlayer.one), BallGroup.stripes);
      expect(rules.state.groupFor(PoolPlayer.two), BallGroup.solids);
    });

    test('potting one of each leaves the table open', () {
      // There is no basis for choosing, and guessing would hand someone a
      // group they never earned.
      rules.applyShot(shot(pocketed: <int>{2, 12}));

      expect(rules.state.isTableOpen, isTrue);
    });

    test('a foul does not assign groups even if a ball dropped', () {
      rules.applyShot(shot(pocketed: <int>{3}, cuePocketed: true));

      expect(rules.state.isTableOpen, isTrue);
    });

    test('groups are assigned once and never reshuffled', () {
      rules
        ..applyShot(shot(pocketed: <int>{3}))
        ..applyShot(shot(pocketed: <int>{11}, firstBallStruck: 3));

      expect(rules.state.groupFor(PoolPlayer.one), BallGroup.solids);
    });
  });

  group('turn order', () {
    test('a legal pot keeps the table', () {
      rules.applyShot(shot(pocketed: <int>{3}));

      expect(rules.state.currentPlayer, PoolPlayer.one);
    });

    test('a legal miss passes the turn', () {
      rules.applyShot(shot());

      expect(rules.state.currentPlayer, PoolPlayer.two);
      expect(rules.state.ballInHand, isFalse, reason: 'a miss is not a foul');
    });

    test('potting the other group does not keep the table', () {
      rules
        ..applyShot(shot(pocketed: <int>{3})) // one is solids
        ..applyShot(shot(pocketed: <int>{11}, firstBallStruck: 3));

      expect(rules.state.currentPlayer, PoolPlayer.two);
    });
  });

  group('fouls', () {
    test('a scratch passes the turn with ball in hand', () {
      rules.applyShot(shot(pocketed: <int>{3}, cuePocketed: true));

      expect(rules.state.currentPlayer, PoolPlayer.two);
      expect(rules.state.lastFoul, PoolFoul.scratch);
      expect(rules.state.ballInHand, isTrue);
    });

    test('hitting nothing is a foul', () {
      rules.applyShot(shot(firstBallStruck: null));

      expect(rules.state.lastFoul, PoolFoul.noContact);
      expect(rules.state.currentPlayer, PoolPlayer.two);
    });

    test('hitting the wrong group first is a foul', () {
      rules
        ..applyShot(shot(pocketed: <int>{3})) // one is solids
        ..applyShot(shot(firstBallStruck: 12));

      expect(rules.state.lastFoul, PoolFoul.wrongBallFirst);
    });

    test('hitting the 8-ball first on an open table is a foul', () {
      rules.applyShot(shot(firstBallStruck: PoolRulesEngine.eightBall));

      expect(rules.state.lastFoul, PoolFoul.wrongBallFirst);
    });

    test('any object ball is a legal first hit on an open table', () {
      rules.applyShot(shot(firstBallStruck: 13));

      expect(rules.state.lastFoul, isNull);
    });

    test('no pot and no cushion is a foul even off the right ball', () {
      rules.applyShot(shot(railContacted: false));

      expect(rules.state.lastFoul, PoolFoul.noRail);
    });

    test('potting a ball satisfies the rail requirement', () {
      rules.applyShot(shot(pocketed: <int>{3}, railContacted: false));

      expect(rules.state.lastFoul, isNull);
    });

    test('a legal shot clears the previous foul', () {
      rules
        ..applyShot(shot(cuePocketed: true))
        ..applyShot(shot(firstBallStruck: 5));

      expect(rules.state.lastFoul, isNull);
      expect(rules.state.ballInHand, isFalse);
    });
  });

  group('shooting the 8-ball', () {
    /// Clear player one's group (solids) without ever passing the turn.
    void clearSolids() {
      rules.applyShot(shot(pocketed: <int>{1}));
      for (final id in <int>[2, 3, 4, 5, 6, 7]) {
        rules.applyShot(shot(pocketed: <int>{id}, firstBallStruck: id));
      }
    }

    test('a player who has cleared their group is on the 8-ball', () {
      clearSolids();

      expect(rules.isOnTheEightBall(PoolPlayer.one), isTrue);
      expect(rules.isOnTheEightBall(PoolPlayer.two), isFalse);
    });

    test('hitting the 8-ball first is legal once on it', () {
      clearSolids();

      rules.applyShot(shot(firstBallStruck: PoolRulesEngine.eightBall));

      expect(rules.state.lastFoul, isNull);
    });

    test('potting the 8-ball after clearing the group wins', () {
      clearSolids();

      rules.applyShot(
        shot(
          pocketed: <int>{PoolRulesEngine.eightBall},
          firstBallStruck: PoolRulesEngine.eightBall,
        ),
      );

      expect(rules.state.winner, PoolPlayer.one);
      expect(rules.state.isGameOver, isTrue);
    });

    test('potting the 8-ball early loses', () {
      rules.applyShot(
        shot(
          pocketed: <int>{PoolRulesEngine.eightBall},
          firstBallStruck: PoolRulesEngine.eightBall,
        ),
      );

      expect(rules.state.winner, PoolPlayer.two);
    });

    test('scratching while potting the 8-ball loses', () {
      clearSolids();

      rules.applyShot(
        shot(
          pocketed: <int>{PoolRulesEngine.eightBall},
          cuePocketed: true,
          firstBallStruck: PoolRulesEngine.eightBall,
        ),
      );

      expect(rules.state.winner, PoolPlayer.two);
    });

    test('the game is frozen once it is over', () {
      rules
        ..applyShot(
          shot(
            pocketed: <int>{PoolRulesEngine.eightBall},
            firstBallStruck: PoolRulesEngine.eightBall,
          ),
        )
        ..applyShot(shot(pocketed: <int>{1}));

      expect(rules.state.winner, PoolPlayer.two);
    });
  });

  group('PoolGameState', () {
    test('value equality covers groups and fouls', () {
      const a = PoolGameState(
        currentPlayer: PoolPlayer.one,
        groups: <PoolPlayer, BallGroup>{PoolPlayer.one: BallGroup.solids},
      );
      const b = PoolGameState(
        currentPlayer: PoolPlayer.one,
        groups: <PoolPlayer, BallGroup>{PoolPlayer.one: BallGroup.solids},
      );
      const c = PoolGameState(
        currentPlayer: PoolPlayer.one,
        groups: <PoolPlayer, BallGroup>{PoolPlayer.one: BallGroup.stripes},
      );
      const d = PoolGameState(
        currentPlayer: PoolPlayer.one,
        lastFoul: PoolFoul.scratch,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('groups expose their ids', () {
      expect(BallGroup.solids.ids, hasLength(7));
      expect(BallGroup.stripes.ids, hasLength(7));
      expect(
        BallGroup.solids.ids.intersection(BallGroup.stripes.ids),
        isEmpty,
      );
      expect(BallGroup.solids.other, BallGroup.stripes);
    });
  });
}
