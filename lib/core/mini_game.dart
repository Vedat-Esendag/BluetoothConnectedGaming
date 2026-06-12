import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:flutter/widgets.dart';

/// Identity + entry point for a single mini-game.
///
/// Every mini-game lives in its own module under `lib/games/<id>/` and exposes
/// exactly one [MiniGameDescriptor]. The shell discovers games through
/// `MiniGameRegistry` and never imports a game's internals — this keeps "many
/// mini-games" additive instead of entangled.
abstract class MiniGameDescriptor {
  /// Stable, unique, lowercase id (e.g. `pool`). Used for routing.
  String get id;

  /// Human-facing title shown in the shell.
  String get title;

  /// Whether this game supports local Bluetooth multiplayer.
  bool get supportsMultiplayer;

  /// Player bounds for a local session.
  int get minPlayers;
  int get maxPlayers;

  /// Build the playable widget. [session] is provided for multiplayer games and
  /// carries the peer transport; single-player games may ignore it.
  Widget build(BuildContext context, {GameSession? session});
}
