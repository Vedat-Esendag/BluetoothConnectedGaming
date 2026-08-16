import 'dart:async';
import 'dart:math';

import 'package:bluetooth_connected_gaming/core/display_name.dart';
import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';

/// Wire keys for the handshake payload (ADR-0011).
abstract final class HandshakeKeys {
  /// The sender's chosen display name.
  static const String name = 'name';

  /// The role the sender believes it holds.
  static const String role = 'role';
}

/// Shown in place of a name the peer sent that was empty or unusable.
const String fallbackPeerName = 'Player 2';

/// Why a handshake did not complete.
enum HandshakeFailure {
  /// The peer never sent a handshake within the timeout.
  timedOut,

  /// The link dropped before the handshake completed.
  disconnected,

  /// The peer's handshake disagreed about roles — both sides claimed host, or
  /// both claimed client.
  roleConflict,
}

/// Raised when [performHandshake] cannot establish a session.
class HandshakeException implements Exception {
  const HandshakeException(this.failure, [this.detail]);

  /// Why the handshake failed.
  final HandshakeFailure failure;

  /// Optional context, for logs only.
  final String? detail;

  @override
  String toString() =>
      'HandshakeException(${failure.name}'
      '${detail == null ? '' : ': $detail'})';
}

/// Exchange display names and confirm roles, producing a [GameSession] (#13).
///
/// Both sides send a handshake as soon as the link is up and wait for the
/// other's. Roles are *not* negotiated — whoever advertised is the host, which
/// the lobby already knows — so the peer's claimed role is only used to detect
/// a genuine mismatch (two hosts, or two clients), which means the two devices
/// disagree about the session and must not start a game.
///
/// The peer's name is untrusted input: it is scrubbed and truncated before it
/// can reach a widget.
Future<GameSession> performHandshake({
  required PeerTransport transport,
  required PeerRole localRole,
  required String localName,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final peerHandshake = Completer<PeerMessage>();
  final subscription = transport.incoming
      .where((m) => m.type == MessageType.handshake.wire)
      .listen(
        (message) {
          if (!peerHandshake.isCompleted) peerHandshake.complete(message);
        },
        // The stream ending, or erroring, before a handshake arrives means the
        // peer went away mid-exchange — not a timeout.
        onDone: () {
          if (!peerHandshake.isCompleted) {
            peerHandshake.completeError(
              const HandshakeException(HandshakeFailure.disconnected),
            );
          }
        },
        onError: (Object error) {
          if (!peerHandshake.isCompleted) {
            peerHandshake.completeError(
              HandshakeException(HandshakeFailure.disconnected, '$error'),
            );
          }
        },
      );

  final PeerMessage message;
  try {
    await transport.send(MessageType.handshake, <String, Object?>{
      HandshakeKeys.name: sanitizeDisplayName(localName, fallback: 'Player'),
      HandshakeKeys.role: localRole.name,
    });
    message = await peerHandshake.future.timeout(
      timeout,
      onTimeout: () =>
          throw const HandshakeException(HandshakeFailure.timedOut),
    );
  } finally {
    await subscription.cancel();
  }

  final claimedRole = message.payload[HandshakeKeys.role];
  if (claimedRole is String && claimedRole == localRole.name) {
    throw const HandshakeException(HandshakeFailure.roleConflict);
  }

  return GameSession(
    transport: transport,
    role: localRole,
    localPlayerId: transport.localPeerId,
    localPlayerName: sanitizeDisplayName(localName, fallback: 'Player'),
    remotePlayerName: sanitizeDisplayName(
      message.payload[HandshakeKeys.name],
      fallback: fallbackPeerName,
    ),
  );
}

/// Generate a peer id valid under [PeerMessage]'s id pattern.
///
/// Ids are per-session and random: nothing about the device is put on the wire,
/// so a NearPlay frame cannot be used to recognise a device across sessions.
String generatePeerId({required PeerRole role, Random? random}) {
  final rng = random ?? Random.secure();
  final suffix = List<String>.generate(
    8,
    (_) => rng.nextInt(16).toRadixString(16),
  ).join();
  return '${role.name}-$suffix';
}
