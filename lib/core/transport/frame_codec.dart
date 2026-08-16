import 'dart:typed_data';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';

/// Byte-length of the frame header: a big-endian uint32 payload length.
const int frameHeaderBytes = 4;

/// Splits a frame into MTU-sized chunks ready for a `PeerConnection` write.
///
/// Prepends the ADR-0010 header (4-byte big-endian length) and cuts the result
/// into pieces of at most [maxChunkBytes]. A chunk boundary carries no meaning:
/// the receiver reassembles from the byte stream, not from chunk edges.
List<Uint8List> chunkFrame(List<int> payload, {required int maxChunkBytes}) {
  if (maxChunkBytes < 1) {
    throw ArgumentError.value(maxChunkBytes, 'maxChunkBytes', 'must be >= 1');
  }
  if (payload.length > PeerMessage.maxFrameBytes) {
    throw ArgumentError.value(
      payload.length,
      'payload',
      'frame exceeds PeerMessage.maxFrameBytes',
    );
  }

  final framed = Uint8List(frameHeaderBytes + payload.length);
  ByteData.view(framed.buffer).setUint32(0, payload.length);
  framed.setRange(frameHeaderBytes, framed.length, payload);

  final chunks = <Uint8List>[];
  for (var offset = 0; offset < framed.length; offset += maxChunkBytes) {
    final end = (offset + maxChunkBytes).clamp(0, framed.length);
    chunks.add(Uint8List.sublistView(framed, offset, end));
  }
  return chunks;
}

/// Raised when the inbound byte stream violates the framing contract.
///
/// Per ADR-0010 this is **not** recoverable: once a length header is bogus every
/// later byte boundary is suspect, so the transport tears the session down
/// rather than trying to resynchronise. Contrast [PeerMessageError], which is
/// one bad message on an otherwise healthy stream.
class FrameProtocolError implements Exception {
  const FrameProtocolError(this.reason);

  /// Why the stream was rejected.
  final String reason;

  @override
  String toString() => 'FrameProtocolError: $reason';
}

/// Reassembles length-prefixed frames from an ordered stream of chunks
/// (ADR-0010).
///
/// This is a security boundary, not just plumbing: the length header is written
/// by the peer, so it is checked against [PeerMessage.maxFrameBytes] *before*
/// anything is allocated on the strength of it. A peer therefore cannot make
/// this buffer grow past that cap, whether by declaring a huge frame or by
/// dribbling chunks that never complete one.
class FrameReassembler {
  final BytesBuilder _buffer = BytesBuilder();

  /// Bytes buffered so far, awaiting a complete frame. Exposed for tests and
  /// diagnostics; never grows past [PeerMessage.maxFrameBytes] + header.
  int get bufferedBytes => _buffer.length;

  /// Feed one inbound [chunk]; returns every frame that completed.
  ///
  /// Throws [FrameProtocolError] if the peer declares an impossible frame
  /// length. The reassembler resets itself before throwing, so a caller that
  /// (wrongly) continues sees a clean buffer rather than a poisoned one. Any
  /// frames that completed earlier in the same chunk are discarded with it —
  /// the session is ending, and a frame that shared a chunk with a malformed
  /// header is not worth delivering.
  List<Uint8List> addChunk(List<int> chunk) {
    _buffer.add(chunk);
    final frames = <Uint8List>[];

    while (true) {
      final buffered = _buffer.toBytes();
      if (buffered.length < frameHeaderBytes) {
        _restore(buffered);
        return frames;
      }

      final length = ByteData.view(
        buffered.buffer,
        buffered.offsetInBytes,
      ).getUint32(0);
      if (length > PeerMessage.maxFrameBytes) {
        reset();
        throw const FrameProtocolError('declared frame length exceeds maximum');
      }

      final total = frameHeaderBytes + length;
      if (buffered.length < total) {
        _restore(buffered);
        return frames;
      }

      frames.add(Uint8List.sublistView(buffered, frameHeaderBytes, total));
      _restore(Uint8List.sublistView(buffered, total));
    }
  }

  /// Drop all buffered bytes.
  void reset() => _buffer.clear();

  void _restore(Uint8List remaining) {
    _buffer
      ..clear()
      ..add(remaining);
  }
}
