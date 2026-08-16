import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:flutter/foundation.dart';

/// Append-only registry of mini-games. Each game registers its descriptor here
/// (in `main.dart` bootstrap). The shell reads this and nothing else, so adding
/// a game is a one-line change with zero edits to existing games.
class MiniGameRegistry {
  MiniGameRegistry._();
  static final MiniGameRegistry instance = MiniGameRegistry._();

  final List<MiniGameDescriptor> _games = [];

  List<MiniGameDescriptor> get games => List.unmodifiable(_games);

  /// Add [descriptor] to the registry.
  ///
  /// A duplicate id throws: ids route to games, so two games answering to the
  /// same one is ambiguous rather than merely untidy — and the likeliest cause
  /// is a scaffolded module whose id was never renamed.
  void register(MiniGameDescriptor descriptor) {
    if (_games.any((g) => g.id == descriptor.id)) {
      throw StateError('Duplicate mini-game id: ${descriptor.id}');
    }
    _games.add(descriptor);
  }

  /// Empty the registry.
  ///
  /// The registry is a singleton, so without this a test that registers a game
  /// leaks into every test that runs after it, and the suite passes or fails
  /// depending on file order.
  @visibleForTesting
  void reset() => _games.clear();
}
