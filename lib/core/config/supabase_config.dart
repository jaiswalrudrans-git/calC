import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Configuration for Metric E2E Backend
///
/// Set your Supabase project credentials below, or pass them during build/run:
/// --dart-define=SUPABASE_URL=https://your-project.supabase.co
/// --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xrjvcbryghzeotfbfgvr.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhyanZjYnJ5Z2h6ZW90ZmJmZ3ZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA0NDU2OTIsImV4cCI6MjEwNjAyMTY5Mn0.kg8zHP9GbRg1J7F-kj0NFqkkQLpI7DcvcXMbESWdwaE',
  );

  static bool get isConfigured =>
      url.isNotEmpty &&
      anonKey.isNotEmpty &&
      !url.contains('placeholder') &&
      !anonKey.contains('placeholder');

  static SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
