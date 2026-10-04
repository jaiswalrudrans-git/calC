import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/firebase_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/notifications/decoy_notification_service.dart';
import 'core/security/secure_key_storage.dart';
import 'core/theme/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/security/signal_crypto.dart';
import 'core/security/privacy_guard.dart';
import 'core/backup/google_drive_backup_service.dart';
import 'features/converter/screens/converter_home_screen.dart';
import 'features/messenger/services/presence_service.dart';

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

  // Instant first-frame render: launch UI immediately without blocking on cloud network handshakes
  runApp(
    const ProviderScope(
      child: MetricApp(),
    ),
  );

  // Background warm-up of Firebase, cryptography, notifications, and cloud services
  _initializeBackgroundServices();
}

Future<void> _initializeBackgroundServices() async {
  try {
    try {
      await FirebaseConfig.init();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[Metric Firebase Init] $e');
    }

    await SignalCryptoService.ensurePrekeyBundle();
    await PrivacyGuard.setScreenProtection(true);
    await GoogleDriveBackupService.instance.init();
    await DecoyNotificationService.instance.init();

    // Start background realtime listener if user is already logged in with contacts
    final myUid = await SecureKeyStorage.getMyDeviceId();
    final contacts = await SecureKeyStorage.getContacts();
    if (myUid != null && myUid.isNotEmpty && contacts.isNotEmpty) {
      DecoyNotificationService.instance.startRealtimeListener(myUid: myUid, contacts: contacts);
    }
  } catch (e) {
    debugPrint('[Metric Services Init] $e');
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MetricApp extends ConsumerStatefulWidget {
  const MetricApp({super.key});

  @override
  ConsumerState<MetricApp> createState() => _MetricAppState();
}

class _MetricAppState extends ConsumerState<MetricApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    PresenceService.instance.onAppLifecycleChanged(state);
    if (state == AppLifecycleState.paused) {
      // INSTANT RESET TO DECOY CONVERTER ON HOME / MINIMIZE
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      PrivacyGuard.markActive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Metric',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const ConverterHomeScreen(),
    );
  }
}
