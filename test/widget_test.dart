import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metric/main.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Map<String, String> mockStorage = {};

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(mockStorage);
    mockStorage.clear();
  });

  testWidgets('Metric App builds successfully into ConverterHomeScreen on launch', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MetricApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify first-launch screen is the innocent Decoy Unit Converter
    expect(find.text('Unit Converter'), findsOneWidget);
    // Verify no chat, auth, or vault traces are visible on the converter screen
    expect(find.text('Chats'), findsNothing);
    expect(find.text('Create Account'), findsNothing);
  });
}
