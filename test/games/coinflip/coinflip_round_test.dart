import 'dart:math';

import 'package:bluetooth_connected_gaming/games/coinflip/coinflip_round.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoinFlipRound', () {
    test('starts with no flips and no score', () {
      const round = CoinFlipRound();
      expect(round.flips, 0);
      expect(round.hostScore, 0);
      expect(round.guestScore, 0);
      expect(round.face, isNull);
      expect(round.guestWasRight, isNull);
    });

    test('a correct call scores for the guest', () {
      final round = const CoinFlipRound().resolve(
        flipped: CoinFace.heads,
        called: CoinFace.heads,
      );

      expect(round.guestScore, 1);
      expect(round.hostScore, 0);
      expect(round.guestWasRight, isTrue);
      expect(round.flips, 1);
    });

    test('a wrong call scores for the host', () {
      final round = const CoinFlipRound().resolve(
        flipped: CoinFace.tails,
        called: CoinFace.heads,
      );

      expect(round.hostScore, 1);
      expect(round.guestScore, 0);
      expect(round.guestWasRight, isFalse);
    });

    test('an uncalled flip scores for nobody', () {
      final round = const CoinFlipRound().resolve(flipped: CoinFace.heads);

      expect(round.hostScore, 0);
      expect(round.guestScore, 0);
      expect(round.flips, 1, reason: 'it still happened');
      expect(round.guestWasRight, isNull);
    });

    test('scores accumulate across rounds', () {
      final round = const CoinFlipRound()
          .resolve(flipped: CoinFace.heads, called: CoinFace.heads)
          .resolve(flipped: CoinFace.heads, called: CoinFace.tails)
          .resolve(flipped: CoinFace.tails, called: CoinFace.tails);

      expect(round.guestScore, 2);
      expect(round.hostScore, 1);
      expect(round.flips, 3);
    });

    test('flip produces both faces over many tries', () {
      final seen = <CoinFace>{
        for (var i = 0; i < 200; i++) CoinFlipRound.flip(Random(i)),
      };
      expect(seen, containsAll(CoinFace.values));
    });

    test('value equality', () {
      const a = CoinFlipRound(face: CoinFace.heads, hostScore: 1);
      const b = CoinFlipRound(face: CoinFace.heads, hostScore: 1);
      const c = CoinFlipRound(face: CoinFace.tails, hostScore: 1);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('faces have display labels', () {
      expect(CoinFace.heads.label, 'Heads');
      expect(CoinFace.tails.label, 'Tails');
    });
  });
}
