import 'dart:typed_data';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';

/// Byte-length of the frame header: a big-endian uint32 payload length.
const int frameHeaderBytes = 4;

/// Smallest payload that could possibly be a valid frame.
///
/// The shortest well-formed [PeerMessage] JSON is far longer than this, but a
/// conservative floor is enough to make degenerate frames — above all the
/// 4-byte `00 00 00 00` that declares an empty payload — a framing violation
/// rather than a cheap way to drive the validate-and-drop path.
const int minFrameBytes = 2;

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
/// anything is allocated on the strength of it. A peer cannot make this buffer
/// grow past that cap, whether by declaring a huge frame, by dribbling chunks
/// that never complete one, or by sending one enormous chunk.
///
/// Pending bytes live in a single buffer with a read offset, and no copy is
/// made until a frame is actually emitted. That matters because the peer
/// chooses the chunk size: re-copying the pending bytes on every chunk would
/// let ~16 KB of 1-byte writes drive hundreds of megabytes of copying.
class FrameReassembler {
  /// The largest the pending buffer may ever be: one maximal frame.
  static const int _capacity = PeerMessage.maxFrameBytes + frameHeaderBytes;

  Uint8List _buffer = Uint8List(0);
  int _start = 0;
  int _end = 0;

  /// Bytes buffered so far, awaiting a complete frame. Never exceeds one
  /// maximal frame.
  int get bufferedBytes => _end - _start;

  /// Feed one inbound [chunk]; returns every frame that completed.
  ///
  /// Throws [FrameProtocolError] if the peer declares an impossible frame
  /// length or overruns the pending-byte cap. The reassembler resets itself
  /// before throwing, so a caller that (wrongly) continues sees a clean buffer
  /// rather than a poisoned one. Any frames that completed earlier in the same
  /// chunk are discarded with it — the session is ending, and a frame that
  /// shared a chunk with a malformed header is not worth delivering.
  List<Uint8List> addChunk(List<int> chunk) {
    if (bufferedBytes + chunk.length > _capacity) {
      reset();
      throw const FrameProtocolError('pending bytes exceed one maximal frame');
    }
    _append(chunk);

    final frames = <Uint8List>[];
    while (bufferedBytes >= frameHeaderBytes) {
      final length = ByteData.view(
        _buffer.buffer,
        _buffer.offsetInBytes + _start,
        frameHeaderBytes,
      ).getUint32(0);

      if (length > PeerMessage.maxFrameBytes || length < minFrameBytes) {
        reset();
        throw const FrameProtocolError('declared frame length is out of range');
      }

      final total = frameHeaderBytes + length;
      if (bufferedBytes < total) break;

      // The only copy: one per emitted frame, so the caller owns its bytes.
      frames.add(
        Uint8List.fromList(
          Uint8List.sublistView(
            _buffer,
            _start + frameHeaderBytes,
            _start + total,
          ),
        ),
      );
      _start += total;
    }

    if (_start == _end) reset();
    return frames;
  }

  /// Drop all buffered bytes.
  void reset() {
    _start = 0;
    _end = 0;
  }

  void _append(List<int> chunk) {
    if (_end + chunk.length > _buffer.length) _makeRoom(chunk.length);
    _buffer.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }

  /// Grow (or merely compact) the buffer so [needed] more bytes fit.
  void _makeRoom(int needed) {
    final pending = bufferedBytes;
    if (pending + needed <= _buffer.length) {
      // Sliding the pending bytes back to zero is enough — no reallocation.
      _buffer.setRange(0, pending, _buffer, _start);
    } else {
      var size = _buffer.isEmpty ? 512 : _buffer.length * 2;
      while (size < pending + needed) {
        size *= 2;
      }
      _buffer = Uint8List(size > _capacity ? _capacity : size)
        ..setRange(0, pending, _buffer, _start);
    }
    _start = 0;
    _end = pending;
  }
}
