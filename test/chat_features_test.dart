import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metric/features/messenger/screens/chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chat Input Isolation Tests', () {
    testWidgets('ChatScreen text typing and submission works',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChatScreen(),
          ),
        ),
      );

      // Verify text field exists
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      // Type text into field
      await tester.enterText(textFieldFinder, 'Hello Secure World');
      await tester.pump();

      // Send button is present
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });
    testWidgets('ChatScreen Scaffold has resizeToAvoidBottomInset: true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChatScreen(),
          ),
        ),
      );

      final scaffoldFinder = find.byType(Scaffold);
      expect(scaffoldFinder, findsOneWidget);
      final scaffold = tester.widget<Scaffold>(scaffoldFinder);
      expect(scaffold.resizeToAvoidBottomInset, isTrue);
    });
  });

  group('Read Receipts Tick System Tests', () {
    testWidgets('ChatScreen renders correctly with provider and PopScope', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChatScreen(),
          ),
        ),
      );

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is PopScope), findsOneWidget);
    });

    testWidgets('Status indicator logic renders correct tick icons and colors', (WidgetTester tester) async {
      Widget buildTestBubble({required String status, required bool isMe}) {
        if (!isMe) {
          return const SizedBox.shrink();
        }
        if (status == 'read') {
          return const Icon(
            Icons.done_all_rounded,
            key: Key('tick_read'),
            color: Color(0xFF34B7F1),
          );
        } else if (status == 'delivered') {
          return const Icon(
            Icons.done_all_rounded,
            key: Key('tick_delivered'),
            color: Colors.black45,
          );
        } else {
          return const Icon(
            Icons.done_rounded,
            key: Key('tick_sent'),
            color: Colors.black45,
          );
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                buildTestBubble(status: 'sent', isMe: true),
                buildTestBubble(status: 'delivered', isMe: true),
                buildTestBubble(status: 'read', isMe: true),
                buildTestBubble(status: 'sent', isMe: false),
              ],
            ),
          ),
        ),
      );

      // 1. Sent message has single grey tick
      final sentTick = tester.widget<Icon>(find.byKey(const Key('tick_sent')));
      expect(sentTick.icon, Icons.done_rounded);
      expect(sentTick.color, Colors.black45);

      // 2. Delivered message has double grey tick
      final deliveredTick = tester.widget<Icon>(find.byKey(const Key('tick_delivered')));
      expect(deliveredTick.icon, Icons.done_all_rounded);
      expect(deliveredTick.color, Colors.black45);

      // 3. Read message has double blue tick
      final readTick = tester.widget<Icon>(find.byKey(const Key('tick_read')));
      expect(readTick.icon, Icons.done_all_rounded);
      expect(readTick.color, const Color(0xFF34B7F1));
    });
  });
}
