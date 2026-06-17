import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:flutter/material.dart';

/// The Flutter overlay drawn on top of the Pool board: a turn indicator while
/// the game is ongoing, or a winner card with a rematch button when it ends.
///
/// Pure presentation — it takes the current [PoolGameState] and a rematch
/// callback, so it can be tested without the Flame game loop.
class PoolHud extends StatelessWidget {
  const PoolHud({required this.state, required this.onRematch, super.key});

  final PoolGameState state;
  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    if (state.isGameOver) {
      return _WinnerCard(winner: state.winner!, onRematch: onRematch);
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Chip(label: Text('${_label(state.currentPlayer)}’s turn')),
          ),
        ),
      ),
    );
  }

  static String _label(PoolPlayer player) =>
      player == PoolPlayer.one ? 'Player 1' : 'Player 2';
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.winner, required this.onRematch});

  final PoolPlayer winner;
  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${PoolHud._label(winner)} wins',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRematch, child: const Text('Rematch')),
            ],
          ),
        ),
      ),
    );
  }
}
