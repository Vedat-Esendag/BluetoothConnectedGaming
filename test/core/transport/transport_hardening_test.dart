import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/transport/frame_codec.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/loopback_peer_connection.dart';

/// Regression tests for the defects the transport security audit found.
///
/// Each one describes the attack or the failure it prevents, so a future
/// refactor that reintroduces the problem fails with an explanation rather than
/// a bare assertion.
void main() {
  group('outbound writes are serialized', () {
    test('concurrent sends do not interleave their chunks', () async {
      final (hostLink, clientLink) = LoopbackPeerConnection.pair();
      final host = PeerConnectionTransport(
        connection: hostLink,
        localPeerId: 'host-1',
      );
      final client = PeerConnectionTransport(
        connection: clientLink,
        localPeerId: 'client-1',
      );

      final received = <int>[];
      final sub = client.incoming.listen((m) => received.add(m.seq));

      // Fire several large frames without awaiting between them. Each frame is
      // many chunks at the 20-byte loopback MTU; if two sends interleaved,
      // the receiver would read a payload byte as a length header and the
      // session would be torn down as a framing violation.
      await Future.wait<void>(<Future<void>>[
        for (var i = 0; i < 6; i++)
          host.send(MessageType.state, <String, Object?>{
            'n': i,
            'padding': 'x' * 200,
          }),
      ]);
      await pumpEventQueue();

      expect(received, <int>[0, 1, 2, 3, 4, 5]);
      expect(
        client.state,
        PeerConnectionState.connected,
        reason: 'interleaved chunks would have killed the session',
      );
      expect(client.droppedFrameCount, 0);

      await sub.cancel();
      await host.disconnect();
      await client.disconnect();
    });

    test('a failed send does not poison later sends', () async {
      final (hostLink, clientLink) = LoopbackPeerConnection.pair();
      final host = PeerConnectionTransport(
        connection: hostLink,
        localPeerId: 'host-1',
      );

      hostLink.dropLink();
      await pumpEventQueue();

      expect(
        () => host.send(MessageType.ping, const <String, Object?>{}),
        throwsA(isA<PeerConnectionClosed>()),
      );
      expect(
        () => host.send(MessageType.ping, const <String, Object?>{}),
        throwsA(isA<PeerConnectionClosed>()),
        reason: 'the queue must not carry the first failure forward',
      );

      await host.disconnect();
      await clientLink.close();
    });
  });

  group('inbound gates', () {
    late LoopbackPeerConnection hostLink;
    late LoopbackPeerConnection clientLink;
    late PeerConnectionTransport client;

    setUp(() {
      (hostLink, clientLink) = LoopbackPeerConnection.pair();
      client = PeerConnectionTransport(
        connection: clientLink,
        localPeerId: 'client-1',
      );
    });

    tearDown(() async {
      await client.disconnect();
      await hostLink.close();
    });

    List<int> frame(Map<String, Object?> json) =>
        chunkFrame(utf8.encode(jsonEncode(json)), maxChunkBytes: 4096).single;

    test(
      'a type outside the ADR-0005 vocabulary never reaches game code',
      () async {
        final seen = <PeerMessage>[];
        final sub = client.incoming.listen(seen.add);

        clientLink.injectIncoming(
          frame(<String, Object?>{
            'v': PeerMessage.wireVersion,
            'type': 'definitely-not-a-real-type',
            'senderId': 'host-1',
            'seq': 1,
            'payload': <String, Object?>{},
          }),
        );
        await pumpEventQueue();

        expect(seen, isEmpty);
        expect(client.droppedFrameCount, 1);
        await sub.cancel();
      },
    );

    test("a peer claiming this device's own id is rejected", () async {
      final seen = <PeerMessage>[];
      final sub = client.incoming.listen(seen.add);

      clientLink.injectIncoming(
        frame(<String, Object?>{
          'v': PeerMessage.wireVersion,
          'type': MessageType.state.wire,
          // Impersonating the local device.
          'senderId': 'client-1',
          'seq': 1,
          'payload': <String, Object?>{},
        }),
      );
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(client.droppedFrameCount, 1);
      await sub.cancel();
    });

    test(
      'no bytes are processed after the session is declared compromised',
      () async {
        final seen = <PeerMessage>[];
        final sub = client.incoming.listen(seen.add, onError: (Object _) {});

        // A framing violation, immediately followed by a perfectly valid frame.
        clientLink
          ..injectIncoming(<int>[0xFF, 0xFF, 0xFF, 0xFF])
          ..injectIncoming(
            frame(<String, Object?>{
              'v': PeerMessage.wireVersion,
              'type': MessageType.state.wire,
              'senderId': 'host-1',
              'seq': 1,
              'payload': <String, Object?>{},
            }),
          );
        await pumpEventQueue();

        expect(
          seen,
          isEmpty,
          reason: 'the session is over; later frames must not slip through',
        );
        await sub.cancel();
      },
    );
  });

  group('reassembler resource bounds', () {
    test('one oversized chunk is refused before it is buffered', () {
      final reassembler = FrameReassembler();
      expect(
        () => reassembler.addChunk(
          Uint8List(PeerMessage.maxFrameBytes + frameHeaderBytes + 1),
        ),
        throwsA(isA<FrameProtocolError>()),
      );
      expect(reassembler.bufferedBytes, 0);
    });

    test('many tiny chunks stay cheap', () {
      // The pathological case: a peer writing one byte at a time. This must not
      // re-copy the pending buffer per chunk (it used to, quadratically).
      final payload = utf8.encode('n' * 8000);
      final framed = chunkFrame(payload, maxChunkBytes: 8192).single;
      final reassembler = FrameReassembler();

      final stopwatch = Stopwatch()..start();
      final frames = <Uint8List>[];
      for (final byte in framed) {
        frames.addAll(reassembler.addChunk(<int>[byte]));
      }
      stopwatch.stop();

      expect(frames.single, payload);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'byte-at-a-time reassembly must not be quadratic',
      );
    });
  });
}
