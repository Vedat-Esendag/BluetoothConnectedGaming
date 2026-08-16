import 'dart:async';
import 'dart:typed_data';

/// Liveness of a [PeerConnection].
enum PeerConnectionState {
  /// Not connected, and not trying to be.
  disconnected,

  /// A link is being established (scanning, connecting, discovering).
  connecting,

  /// A link is up and bytes can flow in both directions.
  connected,
}

/// A duplex, ordered byte channel to exactly one peer (#10).
///
/// This is the whole surface the transport layer needs from Bluetooth, and it
/// is deliberately radio-free: no BLE types, no `flutter_blue_plus`, no
/// `bluetooth_low_energy`. Everything above it — `PeerTransport`, the session
/// layer, every game — depends only on this, which is what lets the loopback
/// double (#11) stand in for a real radio in tests.
///
/// **Contract for implementations:**
/// - [incomingBytes] delivers chunks **in send order**. The framing layer
///   (ADR-0010) relies on that ordering and cannot recover without it.
/// - Chunks may be split or coalesced arbitrarily; a listener must not assume a
///   chunk is one logical frame.
/// - [maxChunkBytes] reflects the negotiated MTU and may grow after connect.
/// - [send] throws [PeerConnectionClosed] when the link is not up.
abstract class PeerConnection {
  /// Stable identifier of the remote device (platform address / remote id).
  String get peerId;

  /// The current link state.
  PeerConnectionState get state;

  /// Link-state transitions. Emits on every change, never the same state twice
  /// in a row.
  Stream<PeerConnectionState> get stateChanges;

  /// Raw inbound chunks, in order.
  Stream<Uint8List> get incomingBytes;

  /// Largest payload a single [send] may carry, from the negotiated MTU. The
  /// framing layer reads this per write, so a later MTU bump takes effect
  /// without reconnecting.
  int get maxChunkBytes;

  /// Write [chunk] to the peer. Must be no larger than [maxChunkBytes].
  Future<void> send(Uint8List chunk);

  /// Close the link and release the underlying resources. Idempotent.
  Future<void> close();
}

/// Thrown when bytes are written to a connection that is not up.
class PeerConnectionClosed implements Exception {
  const PeerConnectionClosed([this.detail]);

  /// Optional context for logs.
  final String? detail;

  @override
  String toString() =>
      'PeerConnectionClosed${detail == null ? '' : ': $detail'}';
}
