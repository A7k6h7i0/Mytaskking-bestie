import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexacorp_call/main.dart';

void main() {
  testWidgets('VoIP call screen renders', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const NexaCorpCallApp());
    await tester.pump();

    expect(find.text('Addphonebook'), findsOneWidget);
    expect(find.text('Sarah Reynolds'), findsOneWidget);
    expect(find.text('ACTIVE CALL'), findsOneWidget);
  });
}
