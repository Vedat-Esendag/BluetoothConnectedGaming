import 'package:bluetooth_connected_gaming/games/pool/pool_game_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds standalone (no external Scaffold) like the real route', (
    tester,
  ) async {
    // Mirrors how main.dart pushes the game: a bare MaterialPageRoute with no
    // surrounding Scaffold/Material. The widget must supply its own — otherwise
    // the HUD's Material widgets (Chip/Card) throw "No Material widget found".
    await tester.pumpWidget(const MaterialApp(home: PoolGameWidget()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(PoolGameWidget), findsOneWidget);
    expect(find.textContaining('Player 1'), findsOneWidget);
  });
}
