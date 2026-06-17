import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoolRulesEngine (minimal 8-ball, pass-and-play)', () {
    test('starts on player one with no winner', () {
      final rules = PoolRulesEngine();
      expect(rules.state.currentPlayer, PoolPlayer.one);
      expect(rules.state.winner, isNull);
      expect(rules.state.isGameOver, isFalse);
    });

    test('pocketing an object ball keeps the same player shooting', () {
      final rules = PoolRulesEngine()
        ..applyShot(pocketed: {3}, cuePocketed: false);
      expect(rules.state.currentPlayer, PoolPlayer.one);
    });

    test('pocketing nothing passes the turn', () {
      final rules = PoolRulesEngine()
        ..applyShot(pocketed: <int>{}, cuePocketed: false);
      expect(rules.state.currentPlayer, PoolPlayer.two);
    });

    test('a scratch (cue pocketed) passes the turn', () {
      final rules = PoolRulesEngine()
        ..applyShot(pocketed: {5}, cuePocketed: true);
      expect(rules.state.currentPlayer, PoolPlayer.two);
    });

    test('pocketing the 8-ball early loses the game for the shooter', () {
      final rules = PoolRulesEngine()
        ..applyShot(pocketed: {PoolRulesEngine.eightBall}, cuePocketed: false);
      expect(rules.state.winner, PoolPlayer.two);
      expect(rules.state.isGameOver, isTrue);
    });

    test('pocketing the 8-ball after clearing the rest wins the game', () {
      final rules = PoolRulesEngine()
        // Player one clears all 14 object balls in one (test) shot, keeps turn.
        ..applyShot(pocketed: _allObjectBalls, cuePocketed: false)
        // ...then legally sinks the 8-ball.
        ..applyShot(pocketed: {PoolRulesEngine.eightBall}, cuePocketed: false);
      expect(rules.state.winner, PoolPlayer.one);
    });

    test(
      'sinking the 8-ball on a scratch loses even if it was the last ball',
      () {
        final rules = PoolRulesEngine()
          ..applyShot(pocketed: _allObjectBalls, cuePocketed: false)
          ..applyShot(pocketed: {PoolRulesEngine.eightBall}, cuePocketed: true);
        expect(rules.state.winner, PoolPlayer.two);
      },
    );
  });
}

/// The 14 non-cue, non-8 object balls.
final Set<int> _allObjectBalls = {
  for (var id = 1; id <= 15; id++)
    if (id != PoolRulesEngine.eightBall) id,
};
