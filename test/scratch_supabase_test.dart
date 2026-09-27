import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:metric/core/config/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('Test message with proper email domain', () async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    final client = Supabase.instance.client;

    // Try with metricapp.io
    print('--- Test 1: Sign up with metricapp.io ---');
    try {
      final res = await client.auth.signUp(
        email: 'testdiag2@metricapp.io',
        password: 'testpass123',
      );
      print('SignUp UID: ${res.user?.id}');
      print('SignUp email confirmed: ${res.user?.emailConfirmedAt}');
    } catch (e) {
      print('SignUp error: $e');
    }

    // Try signing in
    print('--- Test 2: Sign in ---');
    try {
      final res = await client.auth.signInWithPassword(
        email: 'testdiag2@metricapp.io',
        password: 'testpass123',
      );
      final uid = res.user?.id ?? 'N/A';
      print('SignIn UID: $uid');
      
      // Try insert with this UID
      final testId = const Uuid().v4();
      try {
        await client.from('messages').insert({
          'id': testId,
          'sender_uid': uid,
          'recipient_uid': uid,
          'ciphertext': 'test_cipher',
          'iv': 'test_iv_hex',
          'mac': 'test_mac',
          'ephemeral_key': 'test_eph',
          'counter': 0,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        print('INSERT with email-auth UID: SUCCESS !!!');
        await client.from('messages').delete().eq('id', testId);
      } catch (e) {
        print('INSERT with email-auth UID: FAILED - $e');
      }
    } catch (e) {
      print('SignIn error: $e');
    }
    
    // Try approach 3: disable email confirm / use anon + custom token
    print('--- Test 3: Anon auth with all required fields ---');
    try {
      final anonRes = await client.auth.signInAnonymously();
      final anonUid = anonRes.user?.id ?? '';
      print('Anon UID: $anonUid');
      
      final testId = const Uuid().v4();
      try {
        await client.from('messages').insert({
          'id': testId,
          'sender_uid': anonUid,
          'recipient_uid': anonUid,
          'ciphertext': 'test_cipher',
          'iv': 'test_iv_hex',
          'mac': 'test_mac_hex',
          'ephemeral_key': 'test_eph_key',
          'counter': 0,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        print('INSERT with anon UID (all fields): SUCCESS !!!');
        await client.from('messages').delete().eq('id', testId);
      } catch (e) {
        print('INSERT with anon UID (all fields): FAILED - $e');
      }
    } catch (e) {
      print('Anon auth error: $e');
    }
  });
}
