import 'package:bluetooth_connected_gaming/core/mini_game.dart';
import 'package:bluetooth_connected_gaming/core/mini_game_registry.dart';
import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal descriptor: the registry only cares about the contract, not about
/// what a game does.
class _FakeGame implements MiniGameDescriptor {
  const _FakeGame(this.id, {this.title = 'Fake'});

  @override
  final String id;

  @override
  final String title;

  @override
  bool get supportsMultiplayer => true;

  @override
  int get minPlayers => 2;

  @override
  int get maxPlayers => 2;

  @override
  Widget build(BuildContext context, {GameSession? session}) =>
      const SizedBox.shrink();
}

void main() {
  final registry = MiniGameRegistry.instance;

  // The registry is a singleton; without this the app's own registrations (or
  // another test's) would leak in and make results depend on file order.
  setUp(registry.reset);
  tearDown(registry.reset);

  test('starts empty', () {
    expect(registry.games, isEmpty);
  });

  test('a registered descriptor appears in games', () {
    const game = _FakeGame('pool');

    registry.register(game);

    expect(registry.games, <MiniGameDescriptor>[game]);
  });

  test('preserves registration order', () {
    registry
      ..register(const _FakeGame('pool'))
      ..register(const _FakeGame('coinflip'))
      ..register(const _FakeGame('darts'));

    expect(
      registry.games.map((g) => g.id),
      <String>['pool', 'coinflip', 'darts'],
    );
  });

  test('a duplicate id is rejected', () {
    registry.register(const _FakeGame('pool'));

    expect(
      () => registry.register(const _FakeGame('pool', title: 'Pool Deluxe')),
      throwsA(isA<StateError>()),
    );
  });

  test('a rejected duplicate leaves the registry untouched', () {
    registry.register(const _FakeGame('pool'));

    expect(
      () => registry.register(const _FakeGame('pool')),
      throwsStateError,
    );
    expect(registry.games, hasLength(1));
  });

  test('games is unmodifiable, so the shell cannot mutate the registry', () {
    registry.register(const _FakeGame('pool'));

    expect(
      () => registry.games.add(const _FakeGame('sneaky')),
      throwsUnsupportedError,
    );
  });
}
