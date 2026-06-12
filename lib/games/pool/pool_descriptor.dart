import 'package:flutter/material.dart';

import '../../core/mini_game.dart';
import '../../core/peer_transport.dart';

/// Stub descriptor for Pool. Demonstrates the module contract; the Flame game
/// and forge2d physics will live alongside this file as they're built.
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
    // TODO: return the Flame GameWidget hosting the pool simulation.
    // Host runs forge2d and broadcasts ball transforms (ADR-0003);
    // client sends shot inputs and renders received state.
    return const Center(child: Text('Pool — coming soon'));
  }
}
