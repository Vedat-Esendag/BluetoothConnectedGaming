import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/games/coinflip/coinflip_screen.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_tokens.dart';
import 'package:flutter/material.dart';

/// Descriptor for Coin Flip (#27).
///
/// The second game in the registry, and the proof that adding one is additive:
/// this module imports `core` and the shared theme, and nothing from
/// `lib/games/pool/`.
class CoinFlipDescriptor implements MiniGameDescriptor {
  const CoinFlipDescriptor();

  @override
  String get id => 'coinflip';

  @override
  String get title => 'Coin Flip';

  @override
  bool get supportsMultiplayer => true;

  @override
  int get minPlayers => 2;

  @override
  int get maxPlayers => 2;

  @override
  Widget build(BuildContext context, {GameSession? session}) {
    if (session == null) {
      // Coin Flip is multiplayer-only: one device flipping its own coin is not
      // a game. The shell routes multiplayer games through the lobby, so this
      // is a programming error rather than something a player can reach.
      return const _NeedsSession();
    }
    return CoinFlipScreen(session: session);
  }
}

class _NeedsSession extends StatelessWidget {
  const _NeedsSession();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coin Flip')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(NearPlaySpacing.xl),
          child: Text(
            'Coin Flip needs a second player. Start it from the game list.',
            style: NearPlayText.body,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
