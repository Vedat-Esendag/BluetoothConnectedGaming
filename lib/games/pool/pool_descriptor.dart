import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_game_widget.dart';
import 'package:flutter/material.dart';

/// Descriptor for Pool. Builds the local pass-and-play game; the headless
/// simulation, rules and rendering live alongside this file (ADR-0008).
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
    // Local pass-and-play for now; [session] is ignored until the transport
    // lands and feeds the same simulation/snapshot (ADR-0008).
    return const PoolGameWidget();
  }
}
