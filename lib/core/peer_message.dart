import 'dart:convert';

/// A message exchanged between peers.
///
/// NOTHING that arrives over the wire is trusted: every inbound frame is parsed
/// through [PeerMessage.fromWire], which validates it and throws on anything
/// malformed, oversized, or out of contract. In a serverless P2P game this
/// validation *is* the security boundary — there is no backend to sanitize
/// input for us. Callers MUST treat a throw as a hostile/garbage packet and
/// drop the frame (and consider dropping the connection).
class PeerMessage {
  const PeerMessage({
    required this.type,
    required this.senderId,
    required this.seq,
    required this.payload,
  });

  /// Wire-level message type. [MessageType] is the canonical vocabulary — build
  /// outbound messages with `MessageType.x.wire`, never a hardcoded literal.
  ///
  /// [fromWire] stays permissive about the *value*: an unrecognized but
  /// well-formed type is not a parse error. Such a frame is dropped by the
  /// dispatcher — it never throws here and never reaches game logic. Dispatch
  /// lives downstream (#13 handshake, #16 transport). See ADR-0005.
  final String type;

  /// Id of the sending peer.
  final String senderId;

  /// Monotonic sequence number; used to drop replays and reordered frames.
  final int seq;

  /// Already-validated, opaque payload.
  final Map<String, Object?> payload;

  /// Current wire protocol version. Bump on any breaking change to the frame
  /// format; [fromWire] rejects any other version, so peers on incompatible
  /// builds fail fast instead of silently mis-parsing. See ADR-0005.
  static const int wireVersion = 1;

  /// Hard cap on a single frame; rejects absurd inputs early.
  static const int maxFrameBytes = 16 * 1024;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  Map<String, Object?> toJson() => {
    'v': wireVersion,
    'type': type,
    'senderId': senderId,
    'seq': seq,
    'payload': payload,
  };

  /// Encode for transmission.
  List<int> toWire() => utf8.encode(jsonEncode(toJson()));

  /// Parse and validate a raw inbound frame. Throws [PeerMessageError] on any
  /// problem. Never returns a partially-trusted object.
  // Kept as a static validation entry point, not a named constructor: this is
  // the security boundary (CLAUDE.md rule #2) and reads as parse-then-trust.
  // ignore: prefer_constructors_over_static_methods
  static PeerMessage fromWire(List<int> bytes) {
    if (bytes.length > maxFrameBytes) {
      throw const PeerMessageError('frame exceeds max size');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const PeerMessageError('frame is not valid UTF-8 JSON');
    }

    if (decoded is! Map<String, Object?>) {
      throw const PeerMessageError('frame is not a JSON object');
    }

    final version = decoded['v'];
    // `int` (not `num`) is deliberate: Dart decodes JSON floats (e.g. 1.0) and
    // overflow-huge values as double, so this also rejects those.
    if (version is! int || version != wireVersion) {
      throw const PeerMessageError('unsupported protocol version');
    }

    final type = decoded['type'];
    final senderId = decoded['senderId'];
    final seq = decoded['seq'];
    final payload = decoded['payload'];

    if (type is! String || type.isEmpty || type.length > 64) {
      throw const PeerMessageError('invalid type');
    }
    if (senderId is! String || !_idPattern.hasMatch(senderId)) {
      throw const PeerMessageError('invalid senderId');
    }
    if (seq is! int || seq < 0) {
      throw const PeerMessageError('invalid seq');
    }
    if (payload is! Map<String, Object?>) {
      throw const PeerMessageError('invalid payload');
    }

    return PeerMessage(
      type: type,
      senderId: senderId,
      seq: seq,
      payload: payload,
    );
  }
}

/// Raised when an inbound frame fails validation. Treat as a hostile packet.
class PeerMessageError implements Exception {
  const PeerMessageError(this.reason);
  final String reason;

  @override
  String toString() => 'PeerMessageError: $reason';
}

/// The defined transport-level message vocabulary.
///
/// [PeerMessage.type] carries the wire string; this enum is the canonical
/// source — callers MUST use `MessageType.x.wire`, never a hardcoded literal (a
/// typo'd literal still parses and only fails at runtime).
///
/// Game-specific data rides in [PeerMessage.payload]; the type vocabulary is a
/// fixed transport concern, so a new game never adds a type (it reuses
/// `input`/`state` with its own payload) — adding a game does not touch core.
/// See ADR-0005.
enum MessageType {
  /// Connection setup and host/client role assignment (#13).
  handshake('handshake'),

  /// Client → host player action (e.g. a Pool shot).
  input('input'),

  /// Host → client authoritative state snapshot (ADR-0003).
  state('state'),

  /// Keepalive / liveness probe.
  ping('ping');

  const MessageType(this.wire);

  /// The on-the-wire string for this type.
  final String wire;

  /// Maps a wire string to its [MessageType], or null if unrecognized.
  static MessageType? tryParse(String value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}
