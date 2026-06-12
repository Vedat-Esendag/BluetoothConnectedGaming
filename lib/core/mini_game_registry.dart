import 'mini_game.dart';

/// Append-only registry of mini-games. Each game registers its descriptor here
/// (in `main.dart` bootstrap). The shell reads this and nothing else, so adding
/// a game is a one-line change with zero edits to existing games.
class MiniGameRegistry {
  MiniGameRegistry._();
  static final MiniGameRegistry instance = MiniGameRegistry._();

  final List<MiniGameDescriptor> _games = [];

  List<MiniGameDescriptor> get games => List.unmodifiable(_games);

  void register(MiniGameDescriptor descriptor) {
    if (_games.any((g) => g.id == descriptor.id)) {
      throw StateError('Duplicate mini-game id: ${descriptor.id}');
    }
    _games.add(descriptor);
  }
}
