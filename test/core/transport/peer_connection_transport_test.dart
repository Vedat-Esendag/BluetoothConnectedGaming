import 'dart:convert';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:bluetooth_connected_gaming/core/transport/frame_codec.dart';
import 'package:bluetooth_connected_gaming/core/transport/loopback_peer_connection.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Raw frame bytes for a message the transport would never build itself —
/// used to feed replays, spoofed senders, and garbage at the inbound gates.
List<int> _rawFrame({
  required String type,
  required String senderId,
  required int seq,
  Map<String, Object?> payload = const <String, Object?>{},
  int version = PeerMessage.wireVersion,
}) {
  final json = jsonEncode(<String, Object?>{
    'v': version,
    'type': type,
    'senderId': senderId,
    'seq': seq,
    'payload': payload,
  });
  return chunkFrame(utf8.encode(json), maxChunkBytes: 4096).single;
}

void main() {
  late LoopbackPeerConnection hostLink;
  late LoopbackPeerConnection clientLink;
  late PeerConnectionTransport host;
  late PeerConnectionTransport client;

  setUp(() {
    (hostLink, clientLink) = LoopbackPeerConnection.pair();
    host = PeerConnectionTransport(
      connection: hostLink,
      localPeerId: 'host-1',
    );
    client = PeerConnectionTransport(
      connection: clientLink,
      localPeerId: 'client-1',
    );
  });

  tearDown(() async {
    await host.disconnect();
    await client.disconnect();
  });

  group('round trip', () {
    test('a message sent by the host arrives intact at the client', () async {
      final received = client.incoming.first;

      await host.send(MessageType.state, <String, Object?>{'balls': 16});

      final message = await received;
      expect(message.type, MessageType.state.wire);
      expect(message.senderId, 'host-1');
      expect(message.payload, <String, Object?>{'balls': 16});
    });

    test('works in both directions', () async {
      final atHost = host.incoming.first;

      await client.send(MessageType.input, <String, Object?>{'power': 0.5});

      expect((await atHost).payload, <String, Object?>{'power': 0.5});
    });

    test(
      'a payload far larger than one BLE chunk survives reassembly',
      () async {
        // 20-byte chunks (the loopback default) — this is ~60 chunks.
        final balls = <Object?>[
          for (var i = 0; i < 16; i++)
            <String, Object?>{'id': i, 'x': i * 1.5, 'y': -i * 0.25},
        ];
        final received = client.incoming.first;

        await host.send(MessageType.state, <String, Object?>{'balls': balls});

        final message = await received;
        expect((message.payload['balls']! as List).length, 16);
        expect(hostLink.sentChunks.length, greaterThan(10));
      },
    );

    test('stamps a strictly increasing sequence number', () async {
      final seen = <int>[];
      final sub = client.incoming.listen((m) => seen.add(m.seq));

      await host.send(MessageType.ping, const <String, Object?>{});
      await host.send(MessageType.ping, const <String, Object?>{});
      await host.send(MessageType.ping, const <String, Object?>{});
      await pumpEventQueue();

      expect(seen, <int>[0, 1, 2]);
      await sub.cancel();
    });

    test('preserves order across interleaved frames', () async {
      final seen = <Object?>[];
      final sub = client.incoming.listen((m) => seen.add(m.payload['n']));

      for (var n = 0; n < 5; n++) {
        await host.send(MessageType.state, <String, Object?>{'n': n});
      }
      await pumpEventQueue();

      expect(seen, <Object?>[0, 1, 2, 3, 4]);
      await sub.cancel();
    });
  });

  group('inbound gates', () {
    test('drops a replayed frame (#29)', () async {
      final seen = <int>[];
      final sub = client.incoming.listen((m) => seen.add(m.seq));

      final frame = _rawFrame(
        type: MessageType.state.wire,
        senderId: 'host-1',
        seq: 7,
      );
      clientLink
        ..injectIncoming(frame)
        ..injectIncoming(frame);
      await pumpEventQueue();

      expect(seen, <int>[7], reason: 'the replay must not reach the game');
      expect(client.droppedFrameCount, 1);
      await sub.cancel();
    });

    test('drops an out-of-order frame with a lower seq', () async {
      final seen = <int>[];
      final sub = client.incoming.listen((m) => seen.add(m.seq));

      clientLink
        ..injectIncoming(
          _rawFrame(type: 'state', senderId: 'host-1', seq: 10),
        )
        ..injectIncoming(_rawFrame(type: 'state', senderId: 'host-1', seq: 4))
        ..injectIncoming(_rawFrame(type: 'state', senderId: 'host-1', seq: 11));
      await pumpEventQueue();

      expect(seen, <int>[10, 11]);
      await sub.cancel();
    });

    test(
      'drops a frame claiming a different sender once identity is pinned',
      () async {
        final seen = <String>[];
        final sub = client.incoming.listen((m) => seen.add(m.senderId));

        clientLink
          ..injectIncoming(_rawFrame(type: 'state', senderId: 'host-1', seq: 1))
          ..injectIncoming(
            _rawFrame(type: 'state', senderId: 'attacker', seq: 2),
          )
          ..injectIncoming(
            _rawFrame(type: 'state', senderId: 'host-1', seq: 3),
          );
        await pumpEventQueue();

        expect(seen, <String>['host-1', 'host-1']);
        expect(client.droppedFrameCount, 1);
        await sub.cancel();
      },
    );

    test('drops a malformed frame without killing the session', () async {
      final seen = <int>[];
      final sub = client.incoming.listen((m) => seen.add(m.seq));

      clientLink
        ..injectIncoming(
          chunkFrame(
            utf8.encode('not json at all'),
            maxChunkBytes: 4096,
          ).single,
        )
        ..injectIncoming(_rawFrame(type: 'state', senderId: 'host-1', seq: 1));
      await pumpEventQueue();

      expect(seen, <int>[1], reason: 'the session survives one bad frame');
      expect(client.state, PeerConnectionState.connected);
      await sub.cancel();
    });

    test('drops a frame on an unsupported protocol version', () async {
      final seen = <int>[];
      final sub = client.incoming.listen((m) => seen.add(m.seq));

      clientLink.injectIncoming(
        _rawFrame(type: 'state', senderId: 'host-1', seq: 1, version: 99),
      );
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(client.droppedFrameCount, 1);
      await sub.cancel();
    });

    test('a framing violation ends the session', () async {
      Object? error;
      final sub = client.incoming.listen(
        (_) {},
        onError: (Object e) => error = e,
      );

      clientLink.injectIncoming(<int>[0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3]);
      await pumpEventQueue();

      expect(error, isA<FrameProtocolError>());
      expect(client.state, PeerConnectionState.disconnected);
      await sub.cancel();
    });
  });

  group('link lifecycle', () {
    test('reports the peer dropping out (#28)', () async {
      final states = <PeerConnectionState>[];
      final sub = client.connectionState.listen(states.add);

      hostLink.dropLink();
      await pumpEventQueue();

      expect(states, contains(PeerConnectionState.disconnected));
      await sub.cancel();
    });

    test(
      'sending on a dropped link throws rather than silently failing',
      () async {
        hostLink.dropLink();
        await pumpEventQueue();

        expect(
          () => host.send(MessageType.ping, const <String, Object?>{}),
          throwsA(isA<PeerConnectionClosed>()),
        );
      },
    );

    test('disconnect is idempotent', () async {
      await host.disconnect();
      await expectLater(host.disconnect(), completes);
    });
  });

  test(
    'a message rejected by the codec never reaches the incoming stream',
    () async {
      // A frame whose seq is negative is invalid per ADR-0005; fromWire throws
      // and the transport drops it.
      final seen = <PeerMessage>[];
      final sub = client.incoming.listen(seen.add);

      clientLink.injectIncoming(
        _rawFrame(type: 'state', senderId: 'host-1', seq: -1),
      );
      await pumpEventQueue();

      expect(seen, isEmpty);
      await sub.cancel();
    },
  );

  test('exposes the local peer id it stamps on outbound frames', () {
    expect(host.localPeerId, 'host-1');
  });

  test('the loopback pair chunks at the worst-case BLE MTU', () async {
    await host.send(MessageType.ping, const <String, Object?>{});
    expect(
      hostLink.sentChunks.every((c) => c.length <= 20),
      isTrue,
    );
  });
}
