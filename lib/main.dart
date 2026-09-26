import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/security/signal_crypto.dart';
import 'core/security/privacy_guard.dart';
import 'core/security/secure_key_storage.dart';
import 'core/security/auth_service.dart';
import 'features/converter/screens/converter_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Transparent Firebase initialization (fails gracefully if config json/plist not yet placed)
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Offline mode or configuration pending
  }

  // Generate or restore hardware-backed Signal Identity Keys
  await SignalCryptoService.ensureIdentityKeys();
  await AuthService.getOrCreateDeviceUid();

  // Screen protection against capture / recording
  await PrivacyGuard.setScreenProtection(true);

  // Set system UI style (edge to edge, transparent bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    const ProviderScope(
      child: MetricApp(),
    ),
  );
}

class MetricApp extends StatefulWidget {
  const MetricApp({super.key});

  @override
  State<MetricApp> createState() => _MetricAppState();
}

class _MetricAppState extends State<MetricApp> with WidgetsBindingObserver {
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
    final bioEnabled = await SecureKeyStorage.isBiometricsEnabled();
    if (bioEnabled) {
      setState(() => _isLocked = true);
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
      PrivacyGuard.shouldLockOnResume().then((shouldLock) async {
        if (shouldLock && mounted) {
          setState(() => _isLocked = true);
          final unlocked = await PrivacyGuard.authenticate();
          if (mounted) {
            setState(() => _isLocked = !unlocked);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Metric',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
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
                color: Theme.of(context).primaryColor.withOpacity(0.12),
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
