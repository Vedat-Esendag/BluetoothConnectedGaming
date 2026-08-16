import 'dart:math';

import 'package:flutter/foundation.dart' show immutable;

/// Which way a coin landed.
enum CoinFace {
  heads,
  tails;

  /// Wire/display label.
  String get label => this == heads ? 'Heads' : 'Tails';
}

/// The state of a coin-flip match: who called it, how it landed, and the
/// running score.
///
/// Pure Dart with no Flutter or transport dependency, so the rules are testable
/// on their own — the same shape as Pool's rules engine, at a fraction of the
/// size.
@immutable
class CoinFlipRound {
  const CoinFlipRound({
    this.face,
    this.call,
    this.hostScore = 0,
    this.guestScore = 0,
    this.flips = 0,
  });

  /// How the last flip landed, or null before the first flip.
  final CoinFace? face;

  /// What the guest called for the last flip, or null if they had not called.
  final CoinFace? call;

  /// Rounds the host has won.
  final int hostScore;

  /// Rounds the guest has won.
  final int guestScore;

  /// How many flips have happened.
  final int flips;

  /// Whether the guest called the last flip correctly.
  bool? get guestWasRight => face == null || call == null ? null : call == face;

  /// Resolve one flip: the guest calls, the host flips.
  ///
  /// The guest wins the round by calling correctly. An uncalled flip scores
  /// nothing — it is just a coin landing.
  CoinFlipRound resolve({required CoinFace flipped, CoinFace? called}) {
    final guestWins = called != null && called == flipped;
    final hostWins = called != null && called != flipped;
    return CoinFlipRound(
      face: flipped,
      call: called,
      hostScore: hostScore + (hostWins ? 1 : 0),
      guestScore: guestScore + (guestWins ? 1 : 0),
      flips: flips + 1,
    );
  }

  /// Flip a fair coin.
  static CoinFace flip([Random? random]) =>
      (random ?? Random()).nextBool() ? CoinFace.heads : CoinFace.tails;

  @override
  bool operator ==(Object other) =>
      other is CoinFlipRound &&
      other.face == face &&
      other.call == call &&
      other.hostScore == hostScore &&
      other.guestScore == guestScore &&
      other.flips == flips;

  @override
  int get hashCode => Object.hash(face, call, hostScore, guestScore, flips);

  @override
  String toString() =>
      'CoinFlipRound(face: $face, call: $call, '
      'score: $hostScore-$guestScore, flips: $flips)';
}
