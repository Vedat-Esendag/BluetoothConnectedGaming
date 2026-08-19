import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:bluetooth_connected_gaming/core/mini_game_registry.dart';
import 'package:bluetooth_connected_gaming/games/coinflip/coinflip_descriptor.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_descriptor.dart';
import 'package:bluetooth_connected_gaming/shell/lobby/lobby_screen.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_theme.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_tokens.dart';
import 'package:bluetooth_connected_gaming/shell/widgets/bluetooth_banner.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _registerGames();
  runApp(const NearPlayApp());
}

void _registerGames() {
  MiniGameRegistry.instance
    ..register(const PoolDescriptor())
    ..register(const CoinFlipDescriptor());
  // Register additional mini-games here — one line each.
}

/// The app shell: a themed [MaterialApp] over the game list.
class NearPlayApp extends StatelessWidget {
  const NearPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NearPlay',
      theme: buildNearPlayTheme(),
      home: const GameListScreen(),
    );
  }
}

/// The home screen: every registered mini-game, and nothing about any of them
/// specifically — the shell reads `MiniGameRegistry` and never a game's
/// internals, which is what keeps adding a game a one-line change.
class GameListScreen extends StatelessWidget {
  const GameListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = MiniGameRegistry.instance.games;
    return Scaffold(
      appBar: AppBar(title: const Text('NearPlay')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BluetoothBanner(),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                NearPlaySpacing.lg,
                NearPlaySpacing.sm,
                NearPlaySpacing.lg,
                NearPlaySpacing.lg,
              ),
              child: Text(
                'Pick a game to play with the phone next to you.',
                style: NearPlayText.body,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: NearPlaySpacing.lg,
                ),
                itemCount: games.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: NearPlaySpacing.md),
                itemBuilder: (context, i) => _GameCard(game: games[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game});

  final MiniGameDescriptor game;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(
          Icons.sports_esports_outlined,
          color: NearPlayColors.brass,
        ),
        title: Text(game.title),
        subtitle: Text(
          game.supportsMultiplayer
              ? '${game.minPlayers}–${game.maxPlayers} players over Bluetooth'
              : 'Single player',
        ),
        trailing: const Icon(Icons.chevron_right),
        shape: const RoundedRectangleBorder(
          borderRadius: NearPlayRadius.cardBorder,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => game.supportsMultiplayer
                // A multiplayer game goes through the lobby, which produces the
                // live session and hands it to `game.build` (#17).
                ? LobbyScreen(game: game)
                : game.build(context),
          ),
        ),
      ),
    );
  }
}
