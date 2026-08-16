import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/transport/frame_codec.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:flutter/foundation.dart';

/// The concrete [PeerTransport] (#16): frames messages onto a byte
/// [PeerConnection] and validates everything coming back.
///
/// This class is where golden rule #2 is actually enforced. Inbound bytes pass
/// four gates before a game ever sees them:
///
/// 1. **Reassembly** — chunks are rejoined into frames, with the peer's declared
///    length bounded so it cannot drive an allocation (ADR-0010).
/// 2. **Validation** — every frame goes through [PeerMessage.fromWire]; a throw
///    means a hostile or garbage frame and the frame is dropped.
/// 3. **Identity** — the first valid frame pins the peer's `senderId`; frames
///    claiming a different sender are dropped. There is exactly one legitimate
///    remote sender in a two-device session.
/// 4. **Replay** — `seq` must strictly increase; replayed or reordered frames
///    are dropped (#29).
///
/// A frame failing 2–4 is dropped silently and the session continues. A framing
/// violation (gate 1) is different: it means the byte boundaries themselves are
/// untrustworthy, so the session is torn down.
class PeerConnectionTransport implements PeerTransport {
  /// Wrap an already-connected [connection]. [localPeerId] must satisfy
  /// [PeerMessage]'s id pattern — it is stamped onto every outbound frame.
  PeerConnectionTransport({
    required PeerConnection connection,
    required String localPeerId,
  }) : _connection = connection,
       _localPeerId = localPeerId {
    _bytesSub = _connection.incomingBytes.listen(
      _onBytes,
      onError: _onStreamError,
    );
    _stateSub = _connection.stateChanges.listen(_onStateChange);
  }

  final PeerConnection _connection;
  final String _localPeerId;

  final FrameReassembler _reassembler = FrameReassembler();
  final StreamController<PeerMessage> _incoming =
      StreamController<PeerMessage>.broadcast();
  final StreamController<PeerConnectionState> _connectionState =
      StreamController<PeerConnectionState>.broadcast();

  StreamSubscription<Uint8List>? _bytesSub;
  StreamSubscription<PeerConnectionState>? _stateSub;

  int _outboundSeq = 0;
  String? _peerId;
  int _lastAcceptedSeq = -1;
  bool _closed = false;

  @override
  String get localPeerId => _localPeerId;

  @override
  Stream<PeerMessage> get incoming => _incoming.stream;

  @override
  Stream<PeerConnectionState> get connectionState => _connectionState.stream;

  @override
  PeerConnectionState get state => _connection.state;

  /// Number of inbound frames rejected by gates 2–4, for diagnostics and the
  /// smoke-test runbook (#26). A steadily climbing count on a healthy link
  /// means the two devices disagree about the protocol.
  int get droppedFrameCount => _droppedFrames;
  int _droppedFrames = 0;

  @override
  Future<void> send(MessageType type, Map<String, Object?> payload) async {
    if (_closed || _connection.state != PeerConnectionState.connected) {
      throw const PeerConnectionClosed('cannot send on a closed transport');
    }
    final message = PeerMessage(
      type: type.wire,
      senderId: _localPeerId,
      seq: _outboundSeq++,
      payload: payload,
    );
    final chunks = chunkFrame(
      message.toWire(),
      maxChunkBytes: _connection.maxChunkBytes,
    );
    for (final chunk in chunks) {
      await _connection.send(chunk);
    }
  }

  @override
  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    await _bytesSub?.cancel();
    await _stateSub?.cancel();
    await _connection.close();
    if (!_connectionState.isClosed) {
      _connectionState.add(PeerConnectionState.disconnected);
    }
    await _incoming.close();
    await _connectionState.close();
  }

  void _onBytes(Uint8List chunk) {
    final List<Uint8List> frames;
    try {
      frames = _reassembler.addChunk(chunk);
    } on FrameProtocolError catch (error) {
      // The stream's byte boundaries are no longer trustworthy (ADR-0010):
      // there is no safe way to resynchronise, so end the session.
      _fail(error);
      return;
    }
    for (final frame in frames) {
      final message = _accept(frame);
      if (message != null && !_incoming.isClosed) _incoming.add(message);
    }
  }

  /// Runs gates 2–4. Returns null for a frame that must not reach game code.
  PeerMessage? _accept(Uint8List frame) {
    final PeerMessage message;
    try {
      message = PeerMessage.fromWire(frame);
    } on PeerMessageError catch (error) {
      _drop('malformed frame: ${error.reason}');
      return null;
    }

    final knownPeer = _peerId;
    if (knownPeer == null) {
      _peerId = message.senderId;
    } else if (message.senderId != knownPeer) {
      _drop('frame from an unexpected sender');
      return null;
    }

    if (message.seq <= _lastAcceptedSeq) {
      _drop('replayed or reordered frame (seq ${message.seq})');
      return null;
    }
    _lastAcceptedSeq = message.seq;
    return message;
  }

  void _drop(String reason) {
    _droppedFrames++;
    // Dropped frames are expected in the presence of a hostile or buggy peer;
    // they are a diagnostic signal, never an error the game has to handle.
    debugPrint('PeerConnectionTransport: dropped frame — $reason');
  }

  void _onStreamError(Object error, StackTrace stackTrace) => _fail(error);

  void _onStateChange(PeerConnectionState state) {
    if (!_connectionState.isClosed) _connectionState.add(state);
    if (state == PeerConnectionState.disconnected) {
      // The peer is gone; the reassembly buffer belongs to a dead stream.
      _reassembler.reset();
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    if (!_incoming.isClosed) _incoming.addError(error);
    unawaited(disconnect());
  }
}
