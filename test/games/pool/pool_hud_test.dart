import 'package:bluetooth_connected_gaming/games/pool/pool_hud.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoolHud', () {
    testWidgets('shows whose turn it is while the game is ongoing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PoolHud(
              state: const PoolGameState(currentPlayer: PoolPlayer.one),
              onRematch: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('Player 1'), findsOneWidget);
      expect(find.text('Rematch'), findsNothing);
    });

    testWidgets('announces the winner and a working rematch button', (
      tester,
    ) async {
      var rematched = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PoolHud(
              state: const PoolGameState(
                currentPlayer: PoolPlayer.two,
                winner: PoolPlayer.two,
              ),
              onRematch: () => rematched = true,
            ),
          ),
        ),
      );

      expect(find.textContaining('Player 2'), findsWidgets);
      expect(find.textContaining('win'), findsOneWidget);

      await tester.tap(find.text('Rematch'));
      expect(rematched, isTrue);
    });
  });
}
