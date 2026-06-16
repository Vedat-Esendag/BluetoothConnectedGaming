import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';

/// Role of a device within a local session.
enum PeerRole { host, client }

/// Abstraction over the local-multiplayer transport.
///
/// v1 is backed by raw BLE via `flutter_blue_plus` (a custom GATT protocol),
/// which works cross-OS (iPhone <-> Android) — see docs/adr/0002, and the
/// `flutter_nearby_connections` deferral in docs/adr/0004. Game code depends
/// ONLY on this interface, never on a concrete transport, so swapping the
/// backend never touches a game.
abstract class PeerTransport {
  /// Become discoverable under [displayName].
  Future<void> startAdvertising(String displayName);

  /// Look for nearby hosts.
  Future<void> startDiscovery();

  /// Connect to a discovered endpoint.
  Future<void> connect(String endpointId);

  /// Send a validated message to the connected peer.
  Future<void> send(PeerMessage message);

  /// Inbound, already-validated messages. Implementations MUST parse raw frames
  /// through [PeerMessage.fromWire] and silently drop frames that fail.
  Stream<PeerMessage> get incoming;

  /// Tear down the connection.
  Future<void> disconnect();
}

/// Per-match context handed to a multiplayer mini-game.
class GameSession {
  const GameSession({
    required this.transport,
    required this.role,
    required this.localPlayerId,
  });

  final PeerTransport transport;
  final PeerRole role;
  final String localPlayerId;

  bool get isHost => role == PeerRole.host;
}
