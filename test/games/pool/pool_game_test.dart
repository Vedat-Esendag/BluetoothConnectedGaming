import 'package:bluetooth_connected_gaming/games/pool/pool_game.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoolGame', () {
    test('a fresh game lets player one shoot', () {
      final game = PoolGame();
      expect(game.canShoot, isTrue);
      expect(
        game.stateNotifier.value,
        const PoolGameState(currentPlayer: PoolPlayer.one),
      );
    });

    test('no shot may be queued while the table is settling', () {
      final game = PoolGame()..shoot(const ShotCommand(angle: 0, power: 1));
      expect(game.canShoot, isFalse);
    });

    test('resetGame restores a clean, shootable opening state', () {
      final game = PoolGame()..shoot(const ShotCommand(angle: 0, power: 0.5));
      expect(game.canShoot, isFalse);

      game.resetGame();

      expect(game.canShoot, isTrue);
      expect(
        game.stateNotifier.value,
        const PoolGameState(currentPlayer: PoolPlayer.one),
      );
    });
  });
}
