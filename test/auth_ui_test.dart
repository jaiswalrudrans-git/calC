import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:metric/core/theme/app_theme.dart';
import 'package:metric/features/auth/auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Map<String, String> mockStorage = {};

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(mockStorage);
    mockStorage.clear();
  });

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: child,
    );
  }

  testWidgets('RecoveryCodeDisplayScreen requires checkbox before enabling proceed button', (tester) async {
    bool confirmed = false;

    await tester.pumpWidget(createTestWidget(
      RecoveryCodeDisplayScreen(
        recoveryCode: 'A7B2-C9D4-E8F6',
        onConfirmed: () {
          confirmed = true;
        },
      ),
    ));

    // Verify recovery code text is displayed
    expect(find.text('A7B2-C9D4-E8F6'), findsOneWidget);

    // Verify warning banner exists
    expect(find.text('NO EMAIL RESET AVAILABLE'), findsOneWidget);

    // "Proceed" button should be disabled initially
    final proceedBtnFinder = find.widgetWithText(FilledButton, 'Confirm Saved to Proceed');
    expect(proceedBtnFinder, findsOneWidget);
    final FilledButton initialBtn = tester.widget(proceedBtnFinder);
    expect(initialBtn.onPressed, isNull);

    // Scroll to and tap the checkbox to confirm
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Now button should be enabled and say "I've Saved It — Proceed"
    final activeBtnFinder = find.widgetWithText(FilledButton, "I've Saved It — Proceed");
    expect(activeBtnFinder, findsOneWidget);
    final FilledButton activeBtn = tester.widget(activeBtnFinder);
    expect(activeBtn.onPressed, isNotNull);

    // Scroll to and tap the active proceed button
    await tester.ensureVisible(activeBtnFinder);
    await tester.pumpAndSettle();
    await tester.tap(activeBtnFinder);
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('LoginScreen shows forgot password button and navigates to reset screen', (tester) async {
    await tester.pumpWidget(createTestWidget(
      const LoginScreen(),
    ));

    expect(find.text('Sign In to Metric'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);

    // Tap "Forgot password?"
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    // Verify ForgotPasswordScreen is displayed
    expect(find.text('Account Recovery'), findsOneWidget);
    expect(find.text('Verify Recovery Code'), findsOneWidget);
  });

  testWidgets('ForgotPasswordScreen transitions to password reset stage when code matches', (tester) async {
    // First, register a user
    final reg = await AccountAuthService.register(
      username: 'sarah',
      password: 'InitialPassword1!',
    );
    final recoveryCode = reg.recoveryCode!;

    await tester.pumpWidget(createTestWidget(
      const ForgotPasswordScreen(initialUsername: 'sarah'),
    ));

    expect(find.text('Account Recovery'), findsOneWidget);

    // Enter recovery code
    await tester.enterText(find.byType(TextField).at(1), recoveryCode);
    await tester.pumpAndSettle();

    // Tap verify
    await tester.tap(find.text('Verify Recovery Code'));
    await tester.pumpAndSettle();

    // Verify Stage 2 is displayed
    expect(find.text('Recovery Code Verified'), findsOneWidget);
    expect(find.text('NEW PASSWORD'), findsOneWidget);
    expect(find.text('Save New Password'), findsOneWidget);
  });

  testWidgets('WelcomeAuthScreen renders Log In and Create Account options', (tester) async {
    await tester.pumpWidget(createTestWidget(
      const WelcomeAuthScreen(),
    ));

    expect(find.text('Metric'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Zero-Knowledge Architecture'), findsOneWidget);
  });

  testWidgets('AccountCodesDisplayScreen renders both codes and enforces confirmation checkbox', (tester) async {
    bool proceeded = false;

    await tester.pumpWidget(createTestWidget(
      AccountCodesDisplayScreen(
        connectCode: '839-201',
        recoveryCode: 'ABCD-EFGH-IJKL',
        onConfirmed: () {
          proceeded = true;
        },
      ),
    ));

    // Both codes visible
    expect(find.text('839-201'), findsOneWidget);
    expect(find.text('ABCD-EFGH-IJKL'), findsOneWidget);
    expect(find.text('CONNECT CODE'), findsOneWidget);
    expect(find.text('RECOVERY CODE'), findsOneWidget);

    // Button disabled initially
    final btnFinder = find.widgetWithText(FilledButton, 'Confirm Saved to Proceed');
    expect(btnFinder, findsOneWidget);
    final FilledButton initialBtn = tester.widget(btnFinder);
    expect(initialBtn.onPressed, isNull);

    // Tap checkbox
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Now button should be enabled
    final activeBtnFinder = find.widgetWithText(FilledButton, 'Proceed to Metric →');
    expect(activeBtnFinder, findsOneWidget);
    await tester.ensureVisible(activeBtnFinder);
    await tester.pumpAndSettle();
    await tester.tap(activeBtnFinder);
    await tester.pumpAndSettle();

    expect(proceeded, isTrue);
  });
}
