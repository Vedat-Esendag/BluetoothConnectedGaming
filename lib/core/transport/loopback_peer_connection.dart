import 'dart:async';

import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:flutter/foundation.dart';

/// An in-process [PeerConnection] pair (#11): whatever one side sends arrives on
/// the other side's [incomingBytes].
///
/// This is the test seam the whole multiplayer stack is developed against. It
/// is a real implementation of the byte contract, not a stub — it chunks at a
/// configurable [maxChunkBytes] so the framing layer's split/reassemble path is
/// exercised exactly as it is over a radio, and it can be told to drop the link
/// so disconnect handling (#28) is testable too.
///
/// Create a connected pair with [LoopbackPeerConnection.pair].
class LoopbackPeerConnection implements PeerConnection {
  LoopbackPeerConnection._({
    required this.peerId,
    required int maxChunkBytes,
    required PeerConnectionState initialState,
  }) : _maxChunkBytes = maxChunkBytes,
       _state = initialState;

  /// Build two connections wired to each other.
  ///
  /// [maxChunkBytes] defaults to 20 — the usable payload of an unnegotiated BLE
  /// MTU, i.e. the worst case a real link presents. Testing at the worst case
  /// means every frame of interest is genuinely split across chunks.
  static (LoopbackPeerConnection, LoopbackPeerConnection) pair({
    String hostId = 'loopback-host',
    String clientId = 'loopback-client',
    int maxChunkBytes = 20,
  }) {
    final host = LoopbackPeerConnection._(
      peerId: clientId,
      maxChunkBytes: maxChunkBytes,
      initialState: PeerConnectionState.connected,
    );
    final client = LoopbackPeerConnection._(
      peerId: hostId,
      maxChunkBytes: maxChunkBytes,
      initialState: PeerConnectionState.connected,
    );
    host._remote = client;
    client._remote = host;
    return (host, client);
  }

  @override
  final String peerId;

  final int _maxChunkBytes;

  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<PeerConnectionState> _stateChanges =
      StreamController<PeerConnectionState>.broadcast();

  LoopbackPeerConnection? _remote;
  PeerConnectionState _state;

  /// Every chunk this side has sent, in order — lets a test assert on the wire
  /// bytes rather than only on what was decoded.
  final List<Uint8List> sentChunks = <Uint8List>[];

  @override
  PeerConnectionState get state => _state;

  @override
  Stream<PeerConnectionState> get stateChanges => _stateChanges.stream;

  @override
  Stream<Uint8List> get incomingBytes => _incoming.stream;

  @override
  int get maxChunkBytes => _maxChunkBytes;

  @override
  Future<void> send(Uint8List chunk) async {
    if (_state != PeerConnectionState.connected) {
      throw const PeerConnectionClosed('loopback link is down');
    }
    if (chunk.length > _maxChunkBytes) {
      throw ArgumentError.value(
        chunk.length,
        'chunk',
        'exceeds maxChunkBytes ($_maxChunkBytes)',
      );
    }
    sentChunks.add(chunk);
    _remote?._deliver(chunk);
  }

  /// Simulate the peer vanishing (out of range, app killed): both ends go to
  /// [PeerConnectionState.disconnected], as a real radio would report.
  void dropLink() {
    _setState(PeerConnectionState.disconnected);
    _remote?._setState(PeerConnectionState.disconnected);
  }

  /// Push a raw chunk onto this side's inbound stream without a peer sending
  /// it — for feeding hostile or malformed bytes at the transport.
  @visibleForTesting
  void injectIncoming(List<int> bytes) => _deliver(Uint8List.fromList(bytes));

  @override
  Future<void> close() async {
    if (_state == PeerConnectionState.disconnected && _incoming.isClosed) {
      return;
    }
    dropLink();
    if (!_incoming.isClosed) await _incoming.close();
    if (!_stateChanges.isClosed) await _stateChanges.close();
  }

  void _deliver(Uint8List chunk) {
    if (_incoming.isClosed) return;
    _incoming.add(chunk);
  }

  void _setState(PeerConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateChanges.isClosed) _stateChanges.add(next);
  }
}
