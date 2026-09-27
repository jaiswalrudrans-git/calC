import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:metric/features/auth/services/account_auth_service.dart';
import 'package:metric/core/security/secure_key_storage.dart';
import 'package:metric/core/security/signal_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock in-memory storage for FlutterSecureStorage during tests
  final Map<String, String> mockStorage = {};

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(mockStorage);
    mockStorage.clear();
  });

  group('Metric AccountAuthService & Recovery Code Flow', () {
    test('Registration generates a 12-char recovery code, 6-digit connect code, and stable permanent UID', () async {
      const username = 'alice';
      const password = 'SecretPassword123!';

      final result = await AccountAuthService.register(
        username: username,
        password: password,
      );

      expect(result.success, isTrue);
      expect(result.recoveryCode, isNotNull);
      expect(result.connectCode, isNotNull);
      expect(result.uid, isNotNull);

      final plainRecoveryCode = result.recoveryCode!;
      final connectCode = result.connectCode!;
      final uid = result.uid!;

      // Connect code format should be 6 digits (XXX-XXX)
      expect(connectCode.length, 7);
      expect(connectCode.replaceAll('-', '').length, 6);
      expect(int.tryParse(connectCode.replaceAll('-', '')), isNotNull);

      // Recovery Code format should be XXXX-XXXX-XXXX (12 alphanumeric chars + 2 dashes)
      expect(plainRecoveryCode.length, 14);
      final normalized = AccountAuthService.normalizeRecoveryCode(plainRecoveryCode);
      expect(normalized.length, 12);

      // Stable UID check
      expect(uid.isNotEmpty, isTrue);
      expect(await SecureKeyStorage.getMyDeviceId(), uid);
      expect(await SecureKeyStorage.getMyConnectCode(), connectCode);

      // Verify that plaintext recovery code and password are NEVER stored anywhere in storage!
      for (final value in mockStorage.values) {
        expect(value.contains(plainRecoveryCode), isFalse);
        expect(value.contains(normalized), isFalse);
        expect(value.contains(password), isFalse);
      }

      // Check stored hashes exist
      final pwdSalt = mockStorage['metric_auth_user_alice_pwd_salt'];
      final pwdHash = mockStorage['metric_auth_user_alice_pwd_hash'];
      final recSalt = mockStorage['metric_auth_user_alice_recovery_salt'];
      final recHash = mockStorage['metric_auth_user_alice_recovery_hash'];

      expect(pwdSalt, isNotNull);
      expect(pwdHash, isNotNull);
      expect(recSalt, isNotNull);
      expect(recHash, isNotNull);

      // Neither salt nor hash should equal plain password or recovery code
      expect(pwdHash, isNot(password));
      expect(recHash, isNot(plainRecoveryCode));
      expect(recHash, isNot(normalized));
    });

    test('Login succeeds with correct credentials and reconnects the SAME stable UID and Connect Code', () async {
      const username = 'bob';
      const password = 'CorrectPassword99';

      final reg = await AccountAuthService.register(
        username: username,
        password: password,
      );
      final originalUid = reg.uid!;
      final originalConnectCode = reg.connectCode!;

      // Log out
      await AccountAuthService.logout();
      expect(await AccountAuthService.isLoggedIn(), isFalse);

      // Test bad password
      final badLogin = await AccountAuthService.login(
        username: username,
        password: 'WrongPassword!',
      );
      expect(badLogin.success, isFalse);
      expect(badLogin.errorMessage, contains('Incorrect password'));

      // Test correct login
      final goodLogin = await AccountAuthService.login(
        username: username,
        password: password,
      );
      expect(goodLogin.success, isTrue);
      expect(goodLogin.uid, originalUid);
      expect(goodLogin.connectCode, originalConnectCode);

      expect(await AccountAuthService.isLoggedIn(), isTrue);
      expect(await AccountAuthService.getCurrentUsername(), 'bob');
      expect(await AccountAuthService.getCurrentUserUid(), originalUid);
      expect(await AccountAuthService.getCurrentConnectCode(), originalConnectCode);
    });

    test('Rate-limiting locks out recovery attempts after 5 consecutive failures', () async {
      const username = 'charlie';
      await AccountAuthService.register(
        username: username,
        password: 'Password123',
      );

      // 4 consecutive bad attempts
      for (int i = 0; i < 4; i++) {
        final res = await AccountAuthService.verifyRecoveryCode(
          username: username,
          recoveryCode: 'WRONG-CODE-0000',
        );
        expect(res.success, isFalse);
        expect(res.isLockedOut, isFalse);
      }

      // 5th bad attempt triggers lockout
      final fifthRes = await AccountAuthService.verifyRecoveryCode(
        username: username,
        recoveryCode: 'WRONG-CODE-0000',
      );
      expect(fifthRes.success, isFalse);
      expect(fifthRes.isLockedOut, isTrue);
      expect(fifthRes.lockoutSeconds, greaterThan(0));

      // Attempt during lockout is immediately rejected
      final blockedRes = await AccountAuthService.verifyRecoveryCode(
        username: username,
        recoveryCode: 'WRONG-CODE-0000',
      );
      expect(blockedRes.success, isFalse);
      expect(blockedRes.isLockedOut, isTrue);
    });

    test('FULL LOOP: register -> get recovery code -> simulate forgetting password -> reset using recovery code -> log in with new password', () async {
      const username = 'diana';
      const initialPassword = 'InitialSecretPassword123';
      const newPassword = 'BrandNewPassword456!';

      // 1. REGISTER
      final regRes = await AccountAuthService.register(
        username: username,
        password: initialPassword,
      );
      expect(regRes.success, isTrue);
      final recoveryCode = regRes.recoveryCode;
      final originalUid = regRes.uid;
      final originalConnectCode = regRes.connectCode;
      expect(recoveryCode, isNotNull);
      expect(originalUid, isNotNull);
      expect(originalConnectCode, isNotNull);

      // 2. SIMULATE FORGETTING PASSWORD
      final failedLogin = await AccountAuthService.login(
        username: username,
        password: 'ForgotMyPassword!',
      );
      expect(failedLogin.success, isFalse);

      // 3. VERIFY RECOVERY CODE
      final codeWithoutDashes = recoveryCode!.replaceAll('-', '').toLowerCase();
      final verifyRes = await AccountAuthService.verifyRecoveryCode(
        username: username,
        recoveryCode: codeWithoutDashes,
      );
      expect(verifyRes.success, isTrue);

      // 4. RESET PASSWORD USING RECOVERY CODE
      final resetRes = await AccountAuthService.resetPassword(
        username: username,
        recoveryCode: recoveryCode,
        newPassword: newPassword,
        generateNewRecoveryCode: true,
      );
      expect(resetRes.success, isTrue);
      expect(resetRes.recoveryCode, isNotNull);
      final newRecoveryCode = resetRes.recoveryCode!;
      expect(newRecoveryCode, isNot(recoveryCode));

      // Old recovery code is now invalid because it was replaced
      final oldCodeRes = await AccountAuthService.verifyRecoveryCode(
        username: username,
        recoveryCode: recoveryCode,
      );
      expect(oldCodeRes.success, isFalse);

      // 5. ATTEMPT LOGIN WITH OLD PASSWORD (MUST FAIL)
      final oldPwdLogin = await AccountAuthService.login(
        username: username,
        password: initialPassword,
      );
      expect(oldPwdLogin.success, isFalse);

      // 6. LOG IN WITH NEW PASSWORD (MUST SUCCEED WITH SAME STABLE UID & CONNECT CODE)
      final newPwdLogin = await AccountAuthService.login(
        username: username,
        password: newPassword,
      );
      expect(newPwdLogin.success, isTrue);
      expect(newPwdLogin.uid, originalUid);
      expect(newPwdLogin.connectCode, originalConnectCode);
      expect(await AccountAuthService.isLoggedIn(), isTrue);
      expect(await AccountAuthService.getCurrentUsername(), 'diana');
      expect(await AccountAuthService.getCurrentUserUid(), originalUid);
      expect(await AccountAuthService.getCurrentConnectCode(), originalConnectCode);

      // 7. NEW RECOVERY CODE WORKS FOR FUTURE RESETS
      final newCodeVerify = await AccountAuthService.verifyRecoveryCode(
        username: username,
        recoveryCode: newRecoveryCode,
      );
      expect(newCodeVerify.success, isTrue);
    });

    test('getCurrentConnectCode() guarantees 6-digit code generation and persistence', () async {
      // 1. Without prior account or code, getCurrentConnectCode generates automatically
      final code = await AccountAuthService.getCurrentConnectCode();
      expect(code, isNotNull);
      expect(code.length, 7); // XXX-XXX
      final digits = code.replaceAll('-', '');
      expect(digits.length, 6);
      expect(int.tryParse(digits), isNotNull);

      // 2. Subsequent call returns the SAME persisted code
      final codeAgain = await AccountAuthService.getCurrentConnectCode();
      expect(codeAgain, equals(code));
    });

    test('SignalCryptoService.pairWithConnectCode establishes symmetrical paired channel', () async {
      // Register Device A
      final regA = await AccountAuthService.register(username: 'deviceA', password: 'PasswordA123!');
      final codeA = regA.connectCode!;

      // Attempt to pair with own code must fail
      expect(
        () async => await SignalCryptoService.pairWithConnectCode(codeA),
        throwsA(isA<Exception>()),
      );

      // Attempt to pair with invalid length code must fail
      expect(
        () async => await SignalCryptoService.pairWithConnectCode('123'),
        throwsA(isA<Exception>()),
      );

      // Pair with valid peer Device B code (e.g. 987-654)
      const peerCodeB = '987-654';
      await SignalCryptoService.pairWithConnectCode(peerCodeB);

      // Verify paired state
      expect(await SecureKeyStorage.isPaired(), isTrue);
      expect(await SecureKeyStorage.getPairedUid(), 'code_987654');
      expect(await SecureKeyStorage.getRootKey(), isNotNull);
      expect(await SecureKeyStorage.getSendChainKey(), isNotNull);
      expect(await SecureKeyStorage.getRecvChainKey(), isNotNull);
    });
  });
}
