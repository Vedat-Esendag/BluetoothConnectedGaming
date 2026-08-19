import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_game_widget.dart';
import 'package:flutter/material.dart';

/// Descriptor for Pool. The headless simulation, rules, rendering and the
/// network binding all live alongside this file (ADR-0008).
class PoolDescriptor implements MiniGameDescriptor {
  const PoolDescriptor();

  @override
  String get id => 'pool';

  @override
  String get title => 'Pool';

  @override
  bool get supportsMultiplayer => true;

  @override
  int get minPlayers => 2;

  @override
  int get maxPlayers => 2;

  @override
  Widget build(BuildContext context, {GameSession? session}) {
    // One widget covers all three modes: with no session it is local
    // pass-and-play, with one it is host or client (ADR-0003, ADR-0008).
    return PoolGameWidget(session: session);
  }
}
