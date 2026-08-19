import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/games/pool/net/pool_net_codec.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_game.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_snapshot.dart';
import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:flutter/foundation.dart';

/// Connects a [PoolGame] to a live [GameSession] (#14, #20, #21).
///
/// This is the only place Pool knows a network exists. The host publishes its
/// authoritative snapshots and applies the shots it is sent; the client renders
/// what arrives and sends its shots up. Neither side's game logic changes shape
/// — the binding just moves the two callbacks `PoolGame` already exposes onto
/// the transport.
///
/// **Broadcast cadence.** The simulation steps at 60 Hz, but a `state` frame is
/// a few hundred bytes and a BLE link at an unnegotiated MTU moves roughly 20
/// bytes a packet. Broadcasting every step would queue frames faster than the
/// radio drains them and the client would fall progressively further behind.
/// The host therefore sends at most [broadcastHz] times a second while the
/// table is moving, and always sends the frame that ends a shot so the two
/// devices agree on the final position and whose turn it is.
class PoolNetworkBinding {
  PoolNetworkBinding({
    required GameSession session,
    required PoolGame game,
    this.broadcastHz = 20,
  }) : _session = session,
       _game = game {
    _incomingSub = _session.transport.incoming.listen(
      _onMessage,
      onError: _onTransportError,
    );
    _connectionNotifier.value = _session.transport.state;
    _connectionSub = _session.transport.connectionState.listen(
      (state) => _connectionNotifier.value = state,
    );

    if (_session.isHost) {
      _game
        ..onAuthoritativeState = _onHostState
        ..onGameReset = () => _forceNextBroadcast = true;
    } else {
      _game.onShotRequested = _onClientShot;
    }
  }

  /// How many authoritative frames a second the host sends while balls move.
  final int broadcastHz;

  final GameSession _session;
  final PoolGame _game;

  final ValueNotifier<PeerConnectionState> _connectionNotifier =
      ValueNotifier<PeerConnectionState>(PeerConnectionState.connected);

  StreamSubscription<PeerMessage>? _incomingSub;
  StreamSubscription<PeerConnectionState>? _connectionSub;

  DateTime? _lastBroadcast;
  PoolGameState? _lastBroadcastState;
  bool _forceNextBroadcast = false;

  /// Live link state, so the game can show the connection-lost overlay (#28).
  ValueListenable<PeerConnectionState> get connection => _connectionNotifier;

  /// Number of peer messages rejected as unusable, for diagnostics.
  int get rejectedMessageCount => _rejected;
  int _rejected = 0;

  void _onHostState(PoolSnapshot snapshot) {
    final gameState = _game.gameState;
    final now = DateTime.now();
    final last = _lastBroadcast;
    final interval = Duration(microseconds: 1000000 ~/ broadcastHz);

    // Turn and winner changes are the frames that must not be dropped: they
    // are what hand control to the other device. A rematch is forced through
    // explicitly rather than relying on the rules state to have changed — a
    // reset from an unplayed table produces the same state it started from,
    // and the client would sit on a stale rack until the next tick.
    final mustSend = _forceNextBroadcast || gameState != _lastBroadcastState;
    _forceNextBroadcast = false;
    if (!mustSend && last != null && now.difference(last) < interval) {
      return;
    }

    _lastBroadcast = now;
    _lastBroadcastState = gameState;
    unawaited(_send(MessageType.state, encodePoolState(snapshot, gameState)));
  }

  void _onClientShot(ShotCommand shot) =>
      unawaited(_send(MessageType.input, encodeShot(shot)));

  void _onMessage(PeerMessage message) {
    if (_session.isHost) {
      if (message.type != MessageType.input.wire) return;
      final shot = decodeShot(message.payload);
      if (shot == null) {
        _rejected++;
        return;
      }
      // The host re-checks turn ownership before this reaches the simulation.
      _game.applyRemoteShot(shot);
      return;
    }

    if (message.type != MessageType.state.wire) return;
    final state = decodePoolState(message.payload);
    if (state == null) {
      // A state frame that fails validation is dropped, not clamped: a client
      // that patched up a bad frame would render a table its host never had.
      _rejected++;
      return;
    }
    _game.applyRemoteState(state.snapshot, state.gameState);
  }

  Future<void> _send(MessageType type, Map<String, Object?> payload) async {
    try {
      await _session.transport.send(type, payload);
    } on PeerConnectionClosed {
      // The link dropped; the connection listener drives the UI response.
      _connectionNotifier.value = PeerConnectionState.disconnected;
    }
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    _connectionNotifier.value = PeerConnectionState.disconnected;
  }

  /// Stop listening and detach from the game.
  Future<void> dispose() async {
    _game
      ..onAuthoritativeState = null
      ..onShotRequested = null
      ..onGameReset = null;
    await _incomingSub?.cancel();
    await _connectionSub?.cancel();
    _connectionNotifier.dispose();
  }
}
