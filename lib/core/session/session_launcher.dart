import 'dart:async';

import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/session/handshake.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection_transport.dart';

/// Turns a connected [PeerConnection] into a ready-to-play [GameSession]
/// (ADR-0011).
///
/// The single funnel both lobby entrances converge on: hosting and joining
/// differ only in how the connection is obtained, so everything after that —
/// wrapping it in a transport, exchanging names, deciding the session is live —
/// is defined once here rather than once per entrance.
class SessionLauncher {
  const SessionLauncher();

  /// Wrap [connection] and complete the handshake.
  ///
  /// [role] comes from the lobby (whoever advertised is the host), not from the
  /// peer. On failure the connection is closed before the error propagates, so
  /// a failed launch never leaves a radio link open.
  Future<GameSession> launch({
    required PeerConnection connection,
    required PeerRole role,
    required String localName,
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) async {
    final transport = PeerConnectionTransport(
      connection: connection,
      localPeerId: generatePeerId(role: role),
    );

    try {
      return await performHandshake(
        transport: transport,
        localRole: role,
        localName: localName,
        timeout: handshakeTimeout,
      );
    } on Object {
      await transport.disconnect();
      rethrow;
    }
  }
}
