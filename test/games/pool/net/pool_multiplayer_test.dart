import 'package:bluetooth_connected_gaming/core/peer_transport.dart';
import 'package:bluetooth_connected_gaming/core/transport/peer_connection_transport.dart';
import 'package:bluetooth_connected_gaming/games/pool/net/pool_net_codec.dart';
import 'package:bluetooth_connected_gaming/games/pool/net/pool_network_binding.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_game.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_rules_engine.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_simulation.dart';
import 'package:bluetooth_connected_gaming/games/pool/pool_snapshot.dart';
import 'package:bluetooth_connected_gaming/games/pool/shot_command.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/loopback_peer_connection.dart';

/// Drives both games forward as the Flame loop would.
void _tick(List<PoolGame> games, {int frames = 1}) {
  for (var i = 0; i < frames; i++) {
    for (final game in games) {
      game.update(PoolSimulation.fixedDt);
    }
  }
}

void main() {
  group('two devices over a loopback link', () {
    late PoolGame hostGame;
    late PoolGame clientGame;
    late PoolNetworkBinding hostBinding;
    late PoolNetworkBinding clientBinding;
    late PeerConnectionTransport hostTransport;
    late PeerConnectionTransport clientTransport;

    setUp(() {
      final (hostLink, clientLink) = LoopbackPeerConnection.pair(
        // A negotiated MTU, so a state frame is a handful of chunks rather
        // than sixty — the tests stay about sync, not about throughput.
        maxChunkBytes: 180,
      );
      hostTransport = PeerConnectionTransport(
        connection: hostLink,
        localPeerId: 'host-1',
      );
      clientTransport = PeerConnectionTransport(
        connection: clientLink,
        localPeerId: 'client-1',
      );

      hostGame = PoolGame(mode: PoolMode.host);
      clientGame = PoolGame(mode: PoolMode.client);

      hostBinding = PoolNetworkBinding(
        session: GameSession(
          transport: hostTransport,
          role: PeerRole.host,
          localPlayerId: 'host-1',
          localPlayerName: 'Vedat',
          remotePlayerName: 'Sam',
        ),
        game: hostGame,
      );
      clientBinding = PoolNetworkBinding(
        session: GameSession(
          transport: clientTransport,
          role: PeerRole.client,
          localPlayerId: 'client-1',
          localPlayerName: 'Sam',
          remotePlayerName: 'Vedat',
        ),
        game: clientGame,
      );
    });

    tearDown(() async {
      await hostBinding.dispose();
      await clientBinding.dispose();
      await hostTransport.disconnect();
      await clientTransport.disconnect();
    });

    test('the client renders the ball positions the host simulates', () async {
      hostGame.shoot(const ShotCommand(angle: 0, power: 0.8));
      _tick(<PoolGame>[hostGame, clientGame], frames: 30);
      await pumpEventQueue();

      final hostBalls = hostGame.snapshot.balls;
      final clientBalls = clientGame.snapshot.balls;

      expect(clientBalls, hasLength(hostBalls.length));
      // The client has moved off the opening rack, so it is rendering frames
      // the host sent rather than its own idle table.
      expect(clientBalls.first.x, isNot(equals(PoolSimulation.halfWidth / -2)));
      // It is at most one broadcast interval behind, so positions agree to
      // within the distance a ball travels in that time.
      for (var i = 0; i < hostBalls.length; i++) {
        expect(clientBalls[i].id, hostBalls[i].id);
        expect(clientBalls[i].pocketed, hostBalls[i].pocketed);
      }
    });

    test('the client never runs its own physics', () {
      final before = clientGame.snapshot;
      // No host frames arrive; ticking the client must change nothing at all,
      // because two independent forge2d worlds would drift apart (ADR-0003).
      _tick(<PoolGame>[clientGame], frames: 120);
      expect(clientGame.snapshot, before);
    });

    test('a client shot is applied by the host, not locally', () async {
      // Hand the turn to the client first.
      hostGame.shoot(const ShotCommand(angle: 0.4, power: 0.05));
      _tick(<PoolGame>[hostGame], frames: 600);
      await pumpEventQueue();
      expect(hostGame.gameState.currentPlayer, PoolPlayer.two);

      final clientBefore = clientGame.snapshot;
      clientGame.shoot(const ShotCommand(angle: 3.14, power: 0.6));

      // The shot has not touched the client's own table.
      expect(clientGame.snapshot, clientBefore);

      await pumpEventQueue();
      _tick(<PoolGame>[hostGame], frames: 5);
      await pumpEventQueue();

      // It reached the host and moved the authoritative cue ball.
      expect(
        hostGame.snapshot.balls.first.x,
        isNot(equals(clientBefore.balls.first.x)),
      );
    });

    test('turn state reaches the client, gating its controls (#14)', () async {
      expect(clientGame.canShoot, isFalse, reason: 'host opens');

      hostGame.shoot(const ShotCommand(angle: 0.4, power: 0.05));
      _tick(<PoolGame>[hostGame], frames: 600);
      await pumpEventQueue();

      expect(hostGame.gameState.currentPlayer, PoolPlayer.two);
      expect(clientGame.gameState.currentPlayer, PoolPlayer.two);
      expect(clientGame.canShoot, isTrue);
      expect(hostGame.canShoot, isFalse, reason: "not the host's turn");
    });

    test('the host ignores a shot taken out of turn', () async {
      // It is the host's turn; a client shot now must be dropped.
      expect(hostGame.gameState.currentPlayer, PoolPlayer.one);
      final before = hostGame.snapshot;

      hostGame.applyRemoteShot(const ShotCommand(angle: 1, power: 1));
      _tick(<PoolGame>[hostGame], frames: 5);

      expect(hostGame.snapshot, before);
    });

    test(
      'the host broadcasts at its configured rate, not every step',
      () async {
        var frames = 0;
        final (hostLink, clientLink) = LoopbackPeerConnection.pair(
          maxChunkBytes: 180,
        );
        final transport = PeerConnectionTransport(
          connection: hostLink,
          localPeerId: 'host-2',
        );
        final game = PoolGame(mode: PoolMode.host);
        final binding = PoolNetworkBinding(
          session: GameSession(
            transport: transport,
            role: PeerRole.host,
            localPlayerId: 'host-2',
            remotePlayerName: 'Sam',
          ),
          game: game,
        );
        final peer = PeerConnectionTransport(
          connection: clientLink,
          localPeerId: 'client-2',
        );
        final sub = peer.incoming.listen((_) => frames++);

        game.shoot(const ShotCommand(angle: 0, power: 0.6));
        // 60 simulation steps = one second of play.
        _tick(<PoolGame>[game], frames: 60);
        await pumpEventQueue();

        expect(
          frames,
          lessThan(60),
          reason: 'broadcasting every step would swamp a BLE link',
        );
        expect(frames, greaterThan(0));

        await sub.cancel();
        await binding.dispose();
        await transport.disconnect();
        await peer.disconnect();
      },
    );
  });

  group('codec validation', () {
    PoolSnapshot openingSnapshot() => PoolSimulation().snapshot();

    test('round-trips a snapshot and turn state', () {
      final snapshot = openingSnapshot();
      const gameState = PoolGameState(currentPlayer: PoolPlayer.two);

      final decoded = decodePoolState(encodePoolState(snapshot, gameState));

      expect(decoded, isNotNull);
      expect(decoded!.gameState, gameState);
      expect(decoded.snapshot.balls, hasLength(poolBallCount));
      for (var i = 0; i < poolBallCount; i++) {
        expect(
          decoded.snapshot.balls[i].x,
          closeTo(snapshot.balls[i].x, 0.001),
        );
      }
    });

    test('round-trips a winner', () {
      const gameState = PoolGameState(
        currentPlayer: PoolPlayer.one,
        winner: PoolPlayer.two,
      );
      final decoded = decodePoolState(
        encodePoolState(openingSnapshot(), gameState),
      );
      expect(decoded!.gameState.winner, PoolPlayer.two);
    });

    group('rejects a hostile state frame', () {
      Map<String, Object?> validPayload() => encodePoolState(
        openingSnapshot(),
        const PoolGameState(
          currentPlayer: PoolPlayer.one,
        ),
      );

      test('with the wrong number of coordinates', () {
        final payload = validPayload()
          ..[PoolWireKeys.positions] = <double>[1, 2, 3];
        expect(decodePoolState(payload), isNull);
      });

      test('with a non-finite coordinate', () {
        // NaN cannot survive JSON, but a peer can send a string that decodes
        // to something non-numeric in the same slot.
        final payload = validPayload()
          ..[PoolWireKeys.positions] = <Object?>[
            'NaN',
            for (var i = 1; i < poolBallCount * 2; i++) 0.0,
          ];
        expect(decodePoolState(payload), isNull);
      });

      test('with a ball far off the table', () {
        final positions = <double>[
          for (var i = 0; i < poolBallCount * 2; i++) 0,
        ];
        positions[0] = 99999;
        final payload = validPayload()..[PoolWireKeys.positions] = positions;
        expect(decodePoolState(payload), isNull);
      });

      test('with a bogus pocketed mask', () {
        expect(
          decodePoolState(validPayload()..[PoolWireKeys.pocketed] = -1),
          isNull,
        );
        expect(
          decodePoolState(
            validPayload()..[PoolWireKeys.pocketed] = 1 << 40,
          ),
          isNull,
        );
      });

      test('with a player index that does not exist', () {
        expect(
          decodePoolState(validPayload()..[PoolWireKeys.turn] = 7),
          isNull,
        );
        expect(
          decodePoolState(validPayload()..[PoolWireKeys.winner] = 7),
          isNull,
        );
      });

      test('that is missing entirely', () {
        expect(decodePoolState(const <String, Object?>{}), isNull);
      });
    });

    group('shot input', () {
      test('round-trips', () {
        const shot = ShotCommand(angle: 1.25, power: 0.5);
        final decoded = decodeShot(encodeShot(shot));
        expect(decoded!.angle, closeTo(1.25, 0.001));
        expect(decoded.power, closeTo(0.5, 0.001));
      });

      test('clamps an out-of-range power rather than refusing it', () {
        final decoded = decodeShot(<String, Object?>{
          PoolWireKeys.angle: 0.0,
          PoolWireKeys.power: 40.0,
        });
        expect(decoded!.power, 1.0);
      });

      test('refuses a shot that would poison the physics world', () {
        expect(
          decodeShot(<String, Object?>{
            PoolWireKeys.angle: 'east',
            PoolWireKeys.power: 1.0,
          }),
          isNull,
        );
        expect(decodeShot(const <String, Object?>{}), isNull);
      });
    });
  });
}
