import 'package:bluetooth_connected_gaming/games/pool/pool_game.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_hud.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_input.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// The playable Pool widget: the Flame board, slingshot drag input, and the
/// turn/winner HUD. Local pass-and-play — no session required.
class PoolGameWidget extends StatefulWidget {
  const PoolGameWidget({super.key});

  @override
  State<PoolGameWidget> createState() => _PoolGameWidgetState();
}

class _PoolGameWidgetState extends State<PoolGameWidget> {
  final PoolGame _game = PoolGame();
  Offset _dragStart = Offset.zero;
  Offset _dragDelta = Offset.zero;

  @override
  void dispose() {
    _game.stateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.biggest.shortestSide * 0.4;
        // Scaffold makes the game self-contained: it is pushed as a bare route
        // (see main.dart) so it must provide its own Material ancestor for the
        // HUD's Material widgets (Chip/Card/FilledButton).
        return Scaffold(
          body: Stack(
            children: [
              GestureDetector(
                onPanStart: (details) => _dragStart = details.localPosition,
                onPanUpdate: (details) =>
                    _dragDelta = details.localPosition - _dragStart,
                onPanEnd: (_) {
                  _game.shoot(
                    shotFromDrag(_dragDelta, maxDragDistance: maxDrag),
                  );
                  _dragDelta = Offset.zero;
                },
                child: GameWidget(game: _game),
              ),
              ValueListenableBuilder<PoolGameState>(
                valueListenable: _game.stateNotifier,
                builder: (context, state, _) =>
                    PoolHud(state: state, onRematch: _game.resetGame),
              ),
            ],
          ),
        );
      },
    );
  }
}
