import 'dart:convert';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeerMessage.fromWire — never trust the peer', () {
    test('round-trips a valid message, payload and all', () {
      const msg = PeerMessage(
        type: 'input',
        senderId: 'player-1',
        seq: 3,
        payload: {
          'k': 'v',
          'n': 1,
          'nested': {'a': 1},
        },
      );
      final parsed = PeerMessage.fromWire(msg.toWire());
      expect(parsed.type, MessageType.input.wire);
      expect(parsed.senderId, 'player-1');
      expect(parsed.seq, 3);
      expect(parsed.payload, msg.payload);
    });

    test('rejects non-JSON frames', () {
      expect(
        () => PeerMessage.fromWire([0xff, 0xfe, 0x00]),
        throwsA(isA<PeerMessageError>()),
      );
    });

    test('rejects oversized frames', () {
      final huge = List<int>.filled(PeerMessage.maxFrameBytes + 1, 0x20);
      expect(
        () => PeerMessage.fromWire(huge),
        throwsA(isA<PeerMessageError>()),
      );
    });

    test('rejects malformed sender ids', () {
      final bad = utf8.encode(
        '{"v":1,"type":"input","senderId":"../etc/passwd","seq":0,"payload":{}}',
      );
      expect(() => PeerMessage.fromWire(bad), throwsA(isA<PeerMessageError>()));
    });

    test('rejects negative sequence numbers', () {
      final bad = utf8.encode(
        '{"v":1,"type":"input","senderId":"p1","seq":-1,"payload":{}}',
      );
      expect(() => PeerMessage.fromWire(bad), throwsA(isA<PeerMessageError>()));
    });

    test('accepts a type at the 64-char limit', () {
      final msg = PeerMessage(
        type: 'a' * 64,
        senderId: 'p1',
        seq: 0,
        payload: const {},
      );
      expect(PeerMessage.fromWire(msg.toWire()).type, 'a' * 64);
    });

    test('rejects a type over the 64-char limit', () {
      final msg = PeerMessage(
        type: 'a' * 65,
        senderId: 'p1',
        seq: 0,
        payload: const {},
      );
      expect(
        () => PeerMessage.fromWire(msg.toWire()),
        throwsA(isA<PeerMessageError>()),
      );
    });

    test('accepts an empty payload', () {
      const msg = PeerMessage(
        type: 'ping',
        senderId: 'p1',
        seq: 0,
        payload: {},
      );
      expect(PeerMessage.fromWire(msg.toWire()).payload, isEmpty);
    });
  });

  group('PeerMessage wire protocol version', () {
    test('toWire stamps the current protocol version', () {
      const msg = PeerMessage(
        type: 'input',
        senderId: 'p1',
        seq: 0,
        payload: {},
      );
      final json =
          jsonDecode(utf8.decode(msg.toWire())) as Map<String, Object?>;
      expect(json['v'], PeerMessage.wireVersion);
    });

    test('rejects a frame with an unsupported version', () {
      final bad = utf8.encode(
        '{"v":2,"type":"input","senderId":"p1","seq":0,"payload":{}}',
      );
      expect(() => PeerMessage.fromWire(bad), throwsA(isA<PeerMessageError>()));
    });

    test('rejects a frame missing the version', () {
      final bad = utf8.encode(
        '{"type":"input","senderId":"p1","seq":0,"payload":{}}',
      );
      expect(() => PeerMessage.fromWire(bad), throwsA(isA<PeerMessageError>()));
    });

    test('rejects a pre-versioning frame (v:0)', () {
      final bad = utf8.encode(
        '{"v":0,"type":"input","senderId":"p1","seq":0,"payload":{}}',
      );
      expect(() => PeerMessage.fromWire(bad), throwsA(isA<PeerMessageError>()));
    });

    test('rejects a non-integer version', () {
      for (final v in ['1.0', 'true', '"1"', 'null']) {
        final bad = utf8.encode(
          '{"v":$v,"type":"input","senderId":"p1","seq":0,"payload":{}}',
        );
        expect(
          () => PeerMessage.fromWire(bad),
          throwsA(isA<PeerMessageError>()),
          reason: 'v:$v must be rejected',
        );
      }
    });
  });

  group('MessageType vocabulary', () {
    test('defines exactly handshake, input, state, ping', () {
      expect(
        MessageType.values.map((t) => t.wire).toSet(),
        {'handshake', 'input', 'state', 'ping'},
      );
    });

    test('tryParse maps known wire strings to their type', () {
      expect(MessageType.tryParse('handshake'), MessageType.handshake);
      expect(MessageType.tryParse('input'), MessageType.input);
      expect(MessageType.tryParse('state'), MessageType.state);
      expect(MessageType.tryParse('ping'), MessageType.ping);
    });

    test('tryParse returns null for an unknown type', () {
      expect(MessageType.tryParse('admin'), isNull);
      // The empty string also maps to null; note it can never reach tryParse
      // via the wire — fromWire rejects an empty type first.
      expect(MessageType.tryParse(''), isNull);
    });

    test('every defined type round-trips and is recoverable', () {
      for (final type in MessageType.values) {
        final msg = PeerMessage(
          type: type.wire,
          senderId: 'p1',
          seq: 1,
          payload: const {'ok': true},
        );
        final parsed = PeerMessage.fromWire(msg.toWire());
        expect(parsed.type, type.wire);
        expect(MessageType.tryParse(parsed.type), type);
      }
    });
  });
}
