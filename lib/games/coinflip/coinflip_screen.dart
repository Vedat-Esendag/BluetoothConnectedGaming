import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/games/coinflip/coinflip_round.dart';
import 'package:bluetooth_connected_gaming/shell/theme/nearplay_tokens.dart';
import 'package:bluetooth_connected_gaming/shell/widgets/connection_overlay.dart';
import 'package:flutter/material.dart';

/// Coin Flip: the guest calls it, the host flips.
///
/// Deliberately the simplest possible complete game, and the second one in the
/// registry — it exists to prove the module contract holds in practice (#27).
/// It reuses `GameSession`, the host-authoritative rule (the host owns the
/// randomness, so there is one truth about how the coin landed), and the shared
/// connection overlay, while sharing no code with Pool.
class CoinFlipScreen extends StatefulWidget {
  const CoinFlipScreen({required this.session, super.key});

  /// The live session; this game is multiplayer-only.
  final GameSession session;

  @override
  State<CoinFlipScreen> createState() => _CoinFlipScreenState();
}

class _CoinFlipScreenState extends State<CoinFlipScreen> {
  static const String _faceKey = 'f';
  static const String _callKey = 'c';
  static const String _hostScoreKey = 'h';
  static const String _guestScoreKey = 'g';
  static const String _flipsKey = 'n';

  CoinFlipRound _round = const CoinFlipRound();
  CoinFace? _pendingCall;
  StreamSubscription<PeerMessage>? _sub;

  bool get _isHost => widget.session.isHost;

  @override
  void initState() {
    super.initState();
    _sub = widget.session.transport.incoming.listen(_onMessage);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _onMessage(PeerMessage message) {
    if (_isHost) {
      if (message.type != MessageType.input.wire) return;
      setState(() => _pendingCall = _faceFrom(message.payload[_callKey]));
      return;
    }
    if (message.type != MessageType.state.wire) return;
    final round = _roundFrom(message.payload);
    if (round == null) return;
    setState(() => _round = round);
  }

  /// The guest's call is the peer's data, so an unrecognised value becomes "no
  /// call" rather than being trusted or crashing the round.
  CoinFace? _faceFrom(Object? value) {
    if (value is! int || value < 0 || value >= CoinFace.values.length) {
      return null;
    }
    return CoinFace.values[value];
  }

  CoinFlipRound? _roundFrom(Map<String, Object?> payload) {
    final hostScore = payload[_hostScoreKey];
    final guestScore = payload[_guestScoreKey];
    final flips = payload[_flipsKey];
    if (hostScore is! int || hostScore < 0) return null;
    if (guestScore is! int || guestScore < 0) return null;
    if (flips is! int || flips < 0) return null;
    return CoinFlipRound(
      face: _faceFrom(payload[_faceKey]),
      call: _faceFrom(payload[_callKey]),
      hostScore: hostScore,
      guestScore: guestScore,
      flips: flips,
    );
  }

  void _flip() {
    final resolved = _round.resolve(
      flipped: CoinFlipRound.flip(),
      called: _pendingCall,
    );
    setState(() {
      _round = resolved;
      _pendingCall = null;
    });
    unawaited(
      widget.session.transport.send(MessageType.state, <String, Object?>{
        _faceKey: resolved.face?.index,
        _callKey: resolved.call?.index,
        _hostScoreKey: resolved.hostScore,
        _guestScoreKey: resolved.guestScore,
        _flipsKey: resolved.flips,
      }),
    );
  }

  void _call(CoinFace face) {
    setState(() => _pendingCall = face);
    unawaited(
      widget.session.transport.send(MessageType.input, <String, Object?>{
        _callKey: face.index,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Coin Flip')),
      body: ConnectionOverlay(
        session: session,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NearPlaySpacing.lg),
            child: Column(
              children: [
                _Scoreboard(
                  round: _round,
                  hostName: _isHost
                      ? session.localPlayerName
                      : session.remotePlayerName,
                  guestName: _isHost
                      ? session.remotePlayerName
                      : session.localPlayerName,
                ),
                const Spacer(),
                _CoinFace(round: _round),
                const Spacer(),
                if (_isHost) ..._hostControls() else ..._guestControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _hostControls() {
    final call = _pendingCall;
    return <Widget>[
      Text(
        call == null
            ? 'Waiting for ${widget.session.remotePlayerName} to call it…'
            : '${widget.session.remotePlayerName} called ${call.label}',
        style: NearPlayText.body,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: NearPlaySpacing.lg),
      FilledButton(
        onPressed: call == null ? null : _flip,
        child: const Text('Flip the coin'),
      ),
    ];
  }

  List<Widget> _guestControls() {
    final called = _pendingCall;
    if (called != null) {
      return <Widget>[
        Text(
          'You called ${called.label}. Waiting for the flip…',
          style: NearPlayText.body,
          textAlign: TextAlign.center,
        ),
      ];
    }
    return <Widget>[
      const Text('Call it', style: NearPlayText.title),
      const SizedBox(height: NearPlaySpacing.lg),
      Row(
        children: <Widget>[
          for (final face in CoinFace.values) ...<Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () => _call(face),
                child: Text(face.label),
              ),
            ),
            if (face != CoinFace.values.last)
              const SizedBox(width: NearPlaySpacing.md),
          ],
        ],
      ),
    ];
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.round,
    required this.hostName,
    required this.guestName,
  });

  final CoinFlipRound round;
  final String hostName;
  final String guestName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _Score(name: hostName, score: round.hostScore),
        Text('${round.flips} flips', style: NearPlayText.caption),
        _Score(name: guestName, score: round.guestScore),
      ],
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.name, required this.score});

  final String name;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text('$score', style: NearPlayText.display),
        Text(name, style: NearPlayText.caption),
      ],
    );
  }
}

class _CoinFace extends StatelessWidget {
  const _CoinFace({required this.round});

  final CoinFlipRound round;

  @override
  Widget build(BuildContext context) {
    final face = round.face;
    return Column(
      children: <Widget>[
        Container(
          width: 140,
          height: 140,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: NearPlayColors.brass,
          ),
          alignment: Alignment.center,
          child: Text(
            face == null ? '?' : face.label[0],
            style: NearPlayText.display.copyWith(
              color: NearPlayColors.onBrass,
              fontSize: 64,
            ),
          ),
        ),
        const SizedBox(height: NearPlaySpacing.lg),
        Text(
          switch (round.guestWasRight) {
            null => face == null ? 'No flips yet' : face.label,
            true => '${face!.label} — called it',
            false => '${face!.label} — wrong call',
          },
          style: NearPlayText.subtitle,
        ),
      ],
    );
  }
}
