// Smoke test for the MyTaskKing app shell. The real app wires Riverpod and
// hits the network, so this test only verifies that the design-system theme
// builds without throwing — enough to catch token typos at CI time.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytaskking_design/mytaskking_design.dart';

void main() {
  testWidgets('Light theme builds without error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: BestieTheme.light(),
      home: const Scaffold(body: Center(child: Text('MyTaskKing'))),
    ));
    expect(find.text('MyTaskKing'), findsOneWidget);
  });

  testWidgets('Dark theme builds without error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: BestieTheme.dark(),
      home: const Scaffold(body: Center(child: Text('MyTaskKing'))),
    ));
    expect(find.text('MyTaskKing'), findsOneWidget);
  });
}
