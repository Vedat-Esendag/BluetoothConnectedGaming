import 'package:bluetooth_connected_gaming/core/mini_game_registry.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_descriptor.dart';
import 'package:flutter/material.dart';

void main() {
  _registerGames();
  runApp(const BluetoothConnectedGamingApp());
}

void _registerGames() {
  MiniGameRegistry.instance.register(const PoolDescriptor());
  // Register additional mini-games here — one line each.
}

class BluetoothConnectedGamingApp extends StatelessWidget {
  const BluetoothConnectedGamingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '<DISPLAY NAME>',
      theme: ThemeData.dark(useMaterial3: true),
      home: const BluetoothConnectedGamingHome(),
    );
  }
}

class BluetoothConnectedGamingHome extends StatelessWidget {
  const BluetoothConnectedGamingHome({super.key});

  @override
  Widget build(BuildContext context) {
    final games = MiniGameRegistry.instance.games;
    return Scaffold(
      appBar: AppBar(title: const Text('<DISPLAY NAME>')),
      body: ListView.builder(
        itemCount: games.length,
        itemBuilder: (context, i) {
          final game = games[i];
          return ListTile(
            title: Text(game.title),
            subtitle: Text(
              game.supportsMultiplayer
                  ? 'Bluetooth multiplayer'
                  : 'Single player',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => game.build(context)),
            ),
          );
        },
      ),
    );
  }
}
