import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_tokens.dart';
import 'package:flutter/material.dart';

/// The overlay drawn on top of the Pool board: a turn indicator while the game
/// is ongoing, or a winner card when it ends (#23).
///
/// Pure presentation — it takes the current [PoolGameState] and player names,
/// so it can be tested without the Flame game loop or a transport.
class PoolHud extends StatelessWidget {
  const PoolHud({
    required this.state,
    required this.onRematch,
    this.localSeat,
    this.hostName = 'Player 1',
    this.guestName = 'Player 2',
    super.key,
  });

  /// Whose turn it is, and whether anyone has won.
  final PoolGameState state;

  /// Restart the match. Null when this device may not restart — on a client,
  /// the host owns the simulation and its next broadcast is the reset.
  final VoidCallback? onRematch;

  /// Which seat this device plays, or null in local pass-and-play where one
  /// device plays both.
  final PoolPlayer? localSeat;

  /// Display name for the host (Player 1).
  final String hostName;

  /// Display name for the joiner (Player 2).
  final String guestName;

  String _name(PoolPlayer player) =>
      player == PoolPlayer.one ? hostName : guestName;

  /// In a two-device match the turn line is about *you*, not about a seat
  /// number — a player should not have to remember which one they are.
  String get _turnLabel {
    final seat = localSeat;
    if (seat == null) return '${_name(state.currentPlayer)}’s turn';
    return state.currentPlayer == seat
        ? 'Your turn'
        : 'Waiting for ${_name(state.currentPlayer)}';
  }

  @override
  Widget build(BuildContext context) {
    if (state.isGameOver) {
      return _WinnerCard(
        title: _winnerTitle,
        onRematch: onRematch,
      );
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.all(NearPlaySpacing.lg),
            child: Chip(label: Text(_turnLabel)),
          ),
        ),
      ),
    );
  }

  String get _winnerTitle {
    final winner = state.winner!;
    final seat = localSeat;
    if (seat == null) return '${_name(winner)} wins';
    return winner == seat ? 'You win' : '${_name(winner)} wins';
  }
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.title, required this.onRematch});

  final String title;
  final VoidCallback? onRematch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(NearPlaySpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, style: NearPlayText.display),
              const SizedBox(height: NearPlaySpacing.lg),
              if (onRematch != null)
                FilledButton(
                  onPressed: onRematch,
                  child: const Text('Rematch'),
                )
              else
                const Text(
                  'Waiting for the host to start a rematch…',
                  style: NearPlayText.body,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
