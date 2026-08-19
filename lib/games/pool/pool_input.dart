import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';

/// Translates a slingshot drag gesture into a [ShotCommand].
///
/// The player drags away from the cue ball and releases; the ball is shot in the
/// *opposite* direction (like a slingshot), with power proportional to the drag
/// length. [dragDelta] is in screen space (y grows downward); the returned angle
/// is in simulation space (y grows upward), so the screen-y is flipped here —
/// this is the input half of the render layer's coordinate mapping (ADR-0008).
ShotCommand shotFromDrag(Offset dragDelta, {required double maxDragDistance}) {
  final power = (dragDelta.distance / maxDragDistance).clamp(0.0, 1.0);
  // Shoot opposite the drag: screen dir (-dx, -dy) -> sim dir (-dx, +dy).
  final angle = math.atan2(dragDelta.dy, -dragDelta.dx);
  return ShotCommand(angle: angle, power: power);
}
