import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/theme/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/security/signal_crypto.dart';
import 'core/security/privacy_guard.dart';
import 'core/security/secure_key_storage.dart';
import 'core/security/auth_service.dart';
import 'features/converter/screens/converter_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI for desktop (Windows / Linux)
  if (Platform.isWindows || Platform.isLinux) {
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    } catch (_) {}
  }

  // Set system UI style (edge to edge, transparent bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Run the app IMMEDIATELY so the user never sees a blank screen!
  runApp(
    const ProviderScope(
      child: MetricApp(),
    ),
  );

  // Background initialization of cryptographic and cloud services
  _initializeBackgroundServices();
}

Future<void> _initializeBackgroundServices() async {
  try {
    if (SupabaseConfig.isConfigured) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
    }
  } catch (e) {
    debugPrint('[Metric Supabase Init] $e');
  }

  try {
    await SignalCryptoService.ensurePrekeyBundle();
    await AuthService.getOrCreateDeviceUid();
    await PrivacyGuard.setScreenProtection(true);
  } catch (e) {
    debugPrint('[Metric Services Init] $e');
  }
}

class MetricApp extends ConsumerStatefulWidget {
  const MetricApp({super.key});

  @override
  ConsumerState<MetricApp> createState() => _MetricAppState();
}

class _MetricAppState extends ConsumerState<MetricApp> with WidgetsBindingObserver {
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialBiometricCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initialBiometricCheck() async {
    // Only lock on startup if the device has been paired
    final isPaired = await SecureKeyStorage.isPaired();
    if (!isPaired) return;

    final canBio = await PrivacyGuard.canCheckBiometrics();
    final bioEnabled = await SecureKeyStorage.isBiometricsEnabled();
    if (canBio && bioEnabled) {
      if (mounted) setState(() => _isLocked = true);
      final unlocked = await PrivacyGuard.authenticate();
      if (mounted) {
        setState(() => _isLocked = !unlocked);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      PrivacyGuard.markActive();
    } else if (state == AppLifecycleState.resumed) {
      SecureKeyStorage.isPaired().then((isPaired) {
        if (!isPaired) return;
        PrivacyGuard.shouldLockOnResume().then((shouldLock) async {
          if (shouldLock && mounted) {
            setState(() => _isLocked = true);
            final unlocked = await PrivacyGuard.authenticate();
            if (mounted) {
              setState(() => _isLocked = !unlocked);
            }
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Metric',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: _isLocked ? _buildLockScreen() : const ConverterHomeScreen(),
    );
  }

  Widget _buildLockScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Metric Locked',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Biometric verification required to access unit vault',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                final unlocked = await PrivacyGuard.authenticate();
                if (mounted && unlocked) {
                  setState(() => _isLocked = false);
                }
              },
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('Unlock with Biometrics'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
