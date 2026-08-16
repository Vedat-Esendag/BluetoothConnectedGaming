import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/transport/frame_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _header(int length) {
  final bytes = Uint8List(frameHeaderBytes);
  ByteData.view(bytes.buffer).setUint32(0, length);
  return bytes;
}

void main() {
  group('chunkFrame', () {
    test('prefixes a big-endian length header', () {
      final chunks = chunkFrame(<int>[1, 2, 3], maxChunkBytes: 64);
      expect(chunks, hasLength(1));
      expect(chunks.single, <int>[0, 0, 0, 3, 1, 2, 3]);
    });

    test('splits at exactly maxChunkBytes', () {
      final payload = List<int>.filled(10, 7);
      final chunks = chunkFrame(payload, maxChunkBytes: 4);
      // 4 header + 10 payload = 14 bytes -> 4 + 4 + 4 + 2
      expect(chunks.map((c) => c.length), <int>[4, 4, 4, 2]);
    });

    test('rejects a payload above the protocol maximum', () {
      expect(
        () => chunkFrame(
          List<int>.filled(PeerMessage.maxFrameBytes + 1, 0),
          maxChunkBytes: 20,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a nonsensical chunk size', () {
      expect(
        () => chunkFrame(<int>[1], maxChunkBytes: 0),
        throwsArgumentError,
      );
    });
  });

  group('FrameReassembler', () {
    test('round-trips a frame split across many chunks', () {
      final payload = utf8.encode('a fairly long NearPlay state frame' * 8);
      final reassembler = FrameReassembler();

      final frames = <Uint8List>[];
      for (final chunk in chunkFrame(payload, maxChunkBytes: 20)) {
        frames.addAll(reassembler.addChunk(chunk));
      }

      expect(frames, hasLength(1));
      expect(frames.single, payload);
      expect(reassembler.bufferedBytes, 0);
    });

    test('emits nothing until the final byte of a frame arrives', () {
      final reassembler = FrameReassembler();
      final chunks = chunkFrame(List<int>.filled(30, 1), maxChunkBytes: 10);

      for (final chunk in chunks.take(chunks.length - 1)) {
        expect(reassembler.addChunk(chunk), isEmpty);
      }
      expect(reassembler.addChunk(chunks.last), hasLength(1));
    });

    test('recovers several frames coalesced into one chunk', () {
      final reassembler = FrameReassembler();
      final joined = <int>[
        ...chunkFrame(<int>[1, 2], maxChunkBytes: 512).single,
        ...chunkFrame(<int>[3, 4, 5], maxChunkBytes: 512).single,
      ];

      final frames = reassembler.addChunk(joined);

      expect(frames, hasLength(2));
      expect(frames[0], <int>[1, 2]);
      expect(frames[1], <int>[3, 4, 5]);
    });

    test('handles a chunk carrying the tail of one frame and the head of the '
        'next', () {
      final reassembler = FrameReassembler();
      final stream = <int>[
        ...chunkFrame(<int>[9, 9], maxChunkBytes: 512).single,
        ...chunkFrame(<int>[8], maxChunkBytes: 512).single,
      ];

      expect(reassembler.addChunk(stream.sublist(0, 4)), isEmpty);
      final frames = reassembler.addChunk(stream.sublist(4));

      expect(frames.map((f) => f.toList()), <List<int>>[
        <int>[9, 9],
        <int>[8],
      ]);
    });

    test('a zero-length frame is a valid frame', () {
      final reassembler = FrameReassembler();
      expect(reassembler.addChunk(_header(0)), <Uint8List>[Uint8List(0)]);
    });

    group('hostile input', () {
      test('rejects a declared length above the protocol maximum', () {
        final reassembler = FrameReassembler();
        expect(
          () => reassembler.addChunk(_header(PeerMessage.maxFrameBytes + 1)),
          throwsA(isA<FrameProtocolError>()),
        );
      });

      test('rejects a 4GB length header without allocating', () {
        final reassembler = FrameReassembler();
        expect(
          () => reassembler.addChunk(<int>[0xFF, 0xFF, 0xFF, 0xFF]),
          throwsA(isA<FrameProtocolError>()),
        );
        expect(reassembler.bufferedBytes, 0);
      });

      test('a peer that never completes a frame cannot grow the buffer past '
          'the cap', () {
        // Declare the largest legal frame, then dribble bytes forever.
        final reassembler = FrameReassembler()
          ..addChunk(_header(PeerMessage.maxFrameBytes));
        for (var i = 0; i < 200; i++) {
          reassembler.addChunk(List<int>.filled(100, 0));
        }

        expect(
          reassembler.bufferedBytes,
          lessThanOrEqualTo(PeerMessage.maxFrameBytes + frameHeaderBytes),
        );
      });

      test('resets its buffer before reporting a protocol error', () {
        final reassembler = FrameReassembler()
          // A frame of length 3, only two bytes of it delivered so far.
          ..addChunk(<int>[0, 0, 0, 3, 1, 2]);
        expect(reassembler.bufferedBytes, greaterThan(0));

        expect(
          // Completes that frame, then opens a frame of 4GB.
          () => reassembler.addChunk(<int>[3, 0xFF, 0xFF, 0xFF, 0xFF]),
          throwsA(isA<FrameProtocolError>()),
        );
        expect(reassembler.bufferedBytes, 0);
      });
    });
  });
}
