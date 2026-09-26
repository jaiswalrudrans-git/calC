import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metric/main.dart';

void main() {
  testWidgets('Metric App builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MetricApp(),
      ),
    );
    expect(find.text('Unit Converter'), findsOneWidget);
  });
}
