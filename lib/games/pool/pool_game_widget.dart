import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/games/pool/net/pool_network_binding.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_game.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_hud.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_input.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:bluetooth_connected_gaming/shell/widgets/connection_overlay.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// The playable Pool widget: the Flame board, slingshot drag input, and the
/// turn/winner HUD.
///
/// One widget serves all three modes. With no [session] it is local
/// pass-and-play; with one it is host or client, and the only difference the
/// widget itself makes is that a networked game is wrapped in the
/// connection-lost overlay and its controls are gated by whose turn it is.
class PoolGameWidget extends StatefulWidget {
  const PoolGameWidget({this.session, super.key});

  /// The live session, or null for local pass-and-play.
  final GameSession? session;

  @override
  State<PoolGameWidget> createState() => _PoolGameWidgetState();
}

class _PoolGameWidgetState extends State<PoolGameWidget> {
  late final PoolGame _game = PoolGame(mode: _mode);
  PoolNetworkBinding? _binding;

  Offset _dragStart = Offset.zero;
  Offset _dragDelta = Offset.zero;

  PoolMode get _mode {
    final session = widget.session;
    if (session == null) return PoolMode.local;
    return session.isHost ? PoolMode.host : PoolMode.client;
  }

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    if (session != null) {
      _binding = PoolNetworkBinding(session: session, game: _game);
    }
  }

  @override
  void dispose() {
    unawaited(_binding?.dispose());
    _game.stateNotifier.dispose();
    super.dispose();
  }

  /// Only the host may restart: it owns the simulation, and its next broadcast
  /// is what resets the client's table.
  VoidCallback? get _onRematch =>
      _mode == PoolMode.client ? null : _game.resetGame;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final board = LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.biggest.shortestSide * 0.4;
        return Stack(
          children: <Widget>[
            GestureDetector(
              onPanStart: (details) => _dragStart = details.localPosition,
              onPanUpdate: (details) =>
                  _dragDelta = details.localPosition - _dragStart,
              onPanEnd: (_) {
                _game.shoot(shotFromDrag(_dragDelta, maxDragDistance: maxDrag));
                _dragDelta = Offset.zero;
              },
              child: GameWidget(game: _game),
            ),
            ValueListenableBuilder<PoolGameState>(
              valueListenable: _game.stateNotifier,
              builder: (context, state, _) => PoolHud(
                state: state,
                onRematch: _onRematch,
                localSeat: _mode == PoolMode.local ? null : _game.localSeat,
                hostName: session?.isHost ?? true
                    ? session?.localPlayerName ?? 'Player 1'
                    : session?.remotePlayerName ?? 'Player 1',
                guestName: session?.isHost ?? true
                    ? session?.remotePlayerName ?? 'Player 2'
                    : session?.localPlayerName ?? 'Player 2',
              ),
            ),
          ],
        );
      },
    );

    // Scaffold makes the game self-contained: it is pushed as a bare route, so
    // it must provide its own Material ancestor for the HUD.
    return Scaffold(
      body: session == null
          ? board
          : ConnectionOverlay(session: session, child: board),
    );
  }
}
