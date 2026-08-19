import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';

/// Role of a device within a local session.
enum PeerRole { host, client }

/// A validated, ordered message channel to the one peer in this session.
///
/// v1 is backed by raw BLE via `bluetooth_low_energy` — the host runs a GATT
/// server, the joiner connects to it (ADR-0006, ADR-0009). Game code depends
/// ONLY on this interface, never on a concrete transport, so swapping the
/// backend never touches a game and the loopback double (#11) is a drop-in.
///
/// **Discovery is not on this interface.** Scanning, advertising, and choosing
/// a peer belong to the lobby (`BleScanner`/`BleHost` and the host/join
/// screen); they produce a connected [PeerConnection], which is what a
/// transport wraps. By the time a game holds a `PeerTransport` the peer is
/// already chosen and connected — see ADR-0011.
abstract class PeerTransport {
  /// This device's peer id, stamped onto every outbound message.
  String get localPeerId;

  /// Inbound messages that passed every check: well-formed per
  /// [PeerMessage.fromWire], not a replay, and genuinely from this peer
  /// (ADR-0010). Anything else never reaches this stream.
  Stream<PeerMessage> get incoming;

  /// Link state, so the shell can react to a peer dropping mid-game (#28).
  Stream<PeerConnectionState> get connectionState;

  /// The current link state.
  PeerConnectionState get state;

  /// Send a message of [type] carrying [payload].
  ///
  /// The transport owns the sequence counter and the sender id — callers cannot
  /// set them, so an outbound frame can never be missing the fields replay
  /// protection depends on.
  Future<void> send(MessageType type, Map<String, Object?> payload);

  /// Tear down the session and release the connection.
  Future<void> disconnect();
}

/// Per-match context handed to a multiplayer mini-game.
class GameSession {
  const GameSession({
    required this.transport,
    required this.role,
    required this.localPlayerId,
    required this.remotePlayerName,
    this.localPlayerName = 'You',
  });

  /// The message channel to the other device.
  final PeerTransport transport;

  /// Whether this device simulates (host) or renders what it is told (client).
  final PeerRole role;

  /// This device's stable player id.
  final String localPlayerId;

  /// Display name of the peer, learned during the handshake (#13).
  final String remotePlayerName;

  /// Display name shown for this device.
  final String localPlayerName;

  /// Whether this device runs the authoritative simulation (ADR-0003).
  bool get isHost => role == PeerRole.host;
}
