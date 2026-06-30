import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytaskking_core/mytaskking_core.dart';
import 'package:mytaskking_windows/main.dart';

void main() {
  testWidgets('shows login screen when signed out', (tester) async {
    final auth = BestieAuthStore();
    final api = BestieApi(baseUrl: 'http://localhost:4000', auth: auth);
    final socket = BestieSocket(url: 'http://localhost:4000', auth: auth);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStoreProvider.overrideWithValue(auth),
          apiProvider.overrideWithValue(api),
          socketProvider.overrideWithValue(socket),
        ],
        child: const BestieWindowsApp(),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
