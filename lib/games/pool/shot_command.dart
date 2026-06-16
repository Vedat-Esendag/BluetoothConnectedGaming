import 'package:flutter/foundation.dart' show immutable;

/// A single shot input: the direction and strength of a cue strike.
///
/// A plain-Dart value type with no Flame/forge2d dependency, so it can later be
/// serialized into a `PeerMessage` `input` payload unchanged (see ADR-0008).
/// The simulation interprets these values; the command itself carries no
/// physics or session state.
@immutable
class ShotCommand {
  const ShotCommand({required this.angle, required this.power});

  /// Aim direction in radians.
  final double angle;

  /// Strike strength, normalised to the range 0..1.
  final double power;

  @override
  bool operator ==(Object other) =>
      other is ShotCommand && other.angle == angle && other.power == power;

  @override
  int get hashCode => Object.hash(angle, power);

  @override
  String toString() => 'ShotCommand(angle: $angle, power: $power)';
}
