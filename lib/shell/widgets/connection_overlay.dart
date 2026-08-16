import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_tokens.dart';
import 'package:flutter/material.dart';

/// Wraps a game and covers it when the peer disconnects (#28).
///
/// Phones get pocketed, locked, and carried out of range mid-game. Without this
/// both devices sit there looking playable while nothing they do reaches the
/// other player. The overlay says plainly that the game is over and offers the
/// one action that works: leave.
///
/// **Reconnect is not offered.** A resumed link would come back with a fresh
/// transport whose replay protection starts from zero (ADR-0010's addendum), so
/// a reconnect is a new session, not a continuation — offering "Reconnect" here
/// would promise a rejoin of *this* game that the transport cannot honour.
/// Leaving and hosting again is the honest path.
class ConnectionOverlay extends StatefulWidget {
  const ConnectionOverlay({
    required this.session,
    required this.child,
    super.key,
  });

  /// The session to watch.
  final GameSession session;

  /// The game underneath.
  final Widget child;

  @override
  State<ConnectionOverlay> createState() => _ConnectionOverlayState();
}

class _ConnectionOverlayState extends State<ConnectionOverlay> {
  late PeerConnectionState _state = widget.session.transport.state;
  StreamSubscription<PeerConnectionState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.session.transport.connectionState.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _leave() async {
    await widget.session.transport.disconnect();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (_state != PeerConnectionState.disconnected) return widget.child;

    return Stack(
      children: <Widget>[
        widget.child,
        ModalBarrier(
          color: NearPlayColors.canvas.withValues(alpha: 0.88),
          dismissible: false,
        ),
        Center(
          child: Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.all(NearPlaySpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.link_off,
                    size: 48,
                    color: NearPlayColors.alert,
                  ),
                  const SizedBox(height: NearPlaySpacing.lg),
                  const Text('Connection lost', style: NearPlayText.title),
                  const SizedBox(height: NearPlaySpacing.sm),
                  Text(
                    '${widget.session.remotePlayerName} is no longer '
                    'connected. Start a new game to play again.',
                    style: NearPlayText.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: NearPlaySpacing.xl),
                  FilledButton(
                    onPressed: () => unawaited(_leave()),
                    child: const Text('Back to games'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
