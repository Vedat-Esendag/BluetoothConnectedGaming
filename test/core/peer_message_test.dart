import 'dart:convert';

import 'package:bluetooth_connected_gaming/core/peer_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeerMessage.fromWire — never trust the peer', () {
    test('round-trips a valid message', () {
      const msg = PeerMessage(
        type: 'input',
        senderId: 'player-1',
        seq: 0,
        payload: {'x': 1},
      );
      final parsed = PeerMessage.fromWire(msg.toWire());
      expect(parsed.type, 'input');
      expect(parsed.senderId, 'player-1');
      expect(parsed.seq, 0);
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
        '{"type":"input","senderId":"../etc/passwd","seq":0,"payload":{}}',
      );
      expect(() => PeerMessage.fromWire(bad), throwsA(isA<PeerMessageError>()));
    });

    test('rejects negative sequence numbers', () {
      final bad = utf8.encode(
        '{"type":"input","senderId":"p1","seq":-1,"payload":{}}',
      );
      expect(() => PeerMessage.fromWire(bad), throwsA(isA<PeerMessageError>()));
    });
  });
}
