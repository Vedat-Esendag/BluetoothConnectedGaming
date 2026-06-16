import 'package:bluetooth_connected_gaming/games/pool/pool_game_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds the board and shows the opening turn indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PoolGameWidget())),
    );
    await tester.pump();

    expect(find.byType(PoolGameWidget), findsOneWidget);
    expect(find.textContaining('Player 1'), findsOneWidget);
  });
}
