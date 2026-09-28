import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/backup/google_drive_backup_service.dart';
import '../../../core/notifications/decoy_notification_service.dart';
import '../../../core/theme/app_colors.dart';
import 'secret_knock_screen.dart';
import '../../auth/auth.dart';
import '../../../../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricsEnabled = true;
  bool _notificationsEnabled = true;
  int _autoLockSeconds = 30;
  bool _isPaired = false;
  String _deviceUid = '';
  String? _peerUid;
  String? _safetyNumber;
  bool _isSafetyVerified = false;
  bool _driveBackupEnabled = false;
  bool _isOwnerDevice = true;
  String? _driveEmail;
  int? _lastSyncTime;
  bool _isSyncing = false;
  String? _syncStatus;
  String? _accountUsername;
  String? _connectCode;
  bool _isAccountLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    GoogleDriveBackupService.instance.isSyncingNotifier.addListener(_onSyncUpdate);
    GoogleDriveBackupService.instance.syncStatusNotifier.addListener(_onSyncStatusUpdate);
  }

  @override
  void dispose() {
    GoogleDriveBackupService.instance.isSyncingNotifier.removeListener(_onSyncUpdate);
    GoogleDriveBackupService.instance.syncStatusNotifier.removeListener(_onSyncStatusUpdate);
    super.dispose();
  }

  void _onSyncUpdate() {
    if (mounted) {
      setState(() {
        _isSyncing = GoogleDriveBackupService.instance.isSyncingNotifier.value;
      });
    }
  }

  void _onSyncStatusUpdate() {
    if (mounted) {
      setState(() {
        _syncStatus = GoogleDriveBackupService.instance.syncStatusNotifier.value;
      });
    }
  }

  Future<void> _loadSettings() async {
    final bio = await SecureKeyStorage.isBiometricsEnabled();
    final autoLock = await SecureKeyStorage.getAutoLockSeconds();
    final paired = await SecureKeyStorage.isPaired();
    final uid = await SecureKeyStorage.getMyDeviceId() ?? 'Not Initialized';
    final peer = await SecureKeyStorage.getPairedUid();
    final safety = await SignalCryptoService.getSafetyNumber();
    final verified = await SecureKeyStorage.isSafetyNumberVerified();
    final isOwner = await SecureKeyStorage.isOwnerDevice();
    final driveEmail = await SecureKeyStorage.getDriveAccountEmail();
    final driveEnabled = await SecureKeyStorage.isDriveBackupEnabled();
    final lastSync = await SecureKeyStorage.getLastDriveSyncTime();
    final accUser = await AccountAuthService.getCurrentUsername();
    final accLoggedIn = await AccountAuthService.isLoggedIn();
    final code = await AccountAuthService.getCurrentConnectCode();
    final notifs = await SecureKeyStorage.getNotificationsEnabled();

    if (mounted) {
      setState(() {
        _biometricsEnabled = bio;
        _notificationsEnabled = notifs;
        _autoLockSeconds = autoLock;
        _isPaired = paired;
        _deviceUid = uid;
        _peerUid = peer;
        _safetyNumber = safety;
        _isSafetyVerified = verified;
        _isOwnerDevice = isOwner;
        _driveEmail = driveEmail;
        _driveBackupEnabled = driveEnabled;
        _lastSyncTime = lastSync;
        _accountUsername = accUser;
        _connectCode = code;
        _isAccountLoggedIn = accLoggedIn;
      });
    }
  }

  void _showAutoLockDialog() {
    final options = [
      {'label': 'Immediately', 'seconds': 0},
      {'label': '30 Seconds', 'seconds': 30},
      {'label': '1 Minute', 'seconds': 60},
      {'label': '5 Minutes', 'seconds': 300},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Auto-Lock Timer'),
        children: options.map((opt) {
          final s = opt['seconds'] as int;
          return SimpleDialogOption(
            onPressed: () async {
              await SecureKeyStorage.setAutoLockSeconds(s);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() => _autoLockSeconds = s);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(opt['label'] as String),
                if (_autoLockSeconds == s)
                  Icon(Icons.check_rounded, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showAccountInfoDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MetricGlass.level1 : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level2 : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.account_circle_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Account Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSecurityBullet('Username', '@${_accountUsername ?? "unknown"}'),
            const SizedBox(height: 6),
            _buildSecurityBullet('Status', 'Active • Logged In'),
            const SizedBox(height: 6),
            _buildSecurityBullet('Encryption', 'Zero-Knowledge E2E'),
            if (_connectCode != null) ...[
              const SizedBox(height: 6),
              _buildSecurityBullet('Connect Code', _connectCode!),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.alertRed),
            SizedBox(width: 10),
            Text('Log Out Account'),
          ],
        ),
        content: const Text(
          'Logging out will remove your active session, unique connect code, pairing keys, and Google Drive connection from this device. Are you sure you want to log out?',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.alertRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    HapticFeedback.mediumImpact();
    await AccountAuthService.logout();

    // Immediately pop all routes back to the root decoy ConverterHomeScreen
    navigatorKey.currentState?.popUntil((route) => route.isFirst);

    final currentCtx = navigatorKey.currentContext;
    if (currentCtx != null && currentCtx.mounted) {
      ScaffoldMessenger.of(currentCtx).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Logged out successfully. All credentials removed.'),
              ),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Local Cache'),
        content: const Text(
          'This will purge local decrypted message cache from this device. Messages remain on the Signal channel until ephemeral expiry.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await LocalDatabaseService.clearAllMessages();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Local decrypted cache cleared')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.alertRed)),
          ),
        ],
      ),
    );
  }

  void _showUnpairDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset & Unpair Connection?'),
        content: const Text(
          'This will purge all cryptographic identity keys, ratchet session state, and local messages. You and your partner will need to pair again with a new code.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await SecureKeyStorage.clearAll();
              await LocalDatabaseService.clearAllMessages();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pairing session reset. All keys purged.'),
                    backgroundColor: AppColors.alertRed,
                  ),
                );
                // Return to Unit Converter decoy screen
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            child: const Text('Unpair & Reset', style: TextStyle(color: AppColors.alertRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showGoogleSignInConfigDialog() {
    const sha1 = '52:E5:ED:46:45:13:78:13:D1:3E:81:FC:9D:3D:B2:76:CE:F4:2C:96';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isDark ? MetricGlass.border : Colors.black12),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level2 : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_sync_rounded, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Google Drive Setup',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Google Sign-In requires your device\'s SHA-1 certificate fingerprint to be registered in your Firebase project (metric-app-af543).',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: isDark ? MetricColors.textSecondary : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'YOUR DEVICE SHA-1 FINGERPRINT:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? MetricGlass.level1 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? MetricGlass.border : Colors.black12),
                ),
                child: const SelectableText(
                  sha1,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: sha1));
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('SHA-1 fingerprint copied to clipboard!'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy SHA-1 to Clipboard'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: isDark ? MetricGlass.border : Colors.black12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Quick Setup in Firebase Console:\n'
                '1. Go to Firebase Console (metric-app-af543) > Project Settings\n'
                '2. Under "Your apps" (Android), click "Add fingerprint"\n'
                '3. Paste this SHA-1 and save\n'
                '4. In Google Cloud Console, enable "Google Drive API"',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: isDark ? MetricColors.textMuted : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? MetricColors.background : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Settings & Privacy'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // E2E Status Section
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level1 : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? MetricGlass.border : Colors.grey.shade300,
                  width: 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? MetricGlass.level2 : Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.verified_user_rounded,
                          color: isDark ? MetricColors.textPrimary : Colors.black87,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Signal Protocol Engine',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark ? MetricColors.textPrimary : Colors.black87,
                              ),
                            ),
                            Text(
                              _isPaired
                                  ? (_isSafetyVerified ? 'Paired & Verified with 1 trusted peer' : 'Paired with 1 peer (Unverified)')
                                  : 'Device not yet paired',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isPaired ? AppColors.secureGreen : AppColors.warningAmber,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: isDark ? MetricGlass.border : Colors.grey.shade300),
                  const SizedBox(height: 6),
                  _buildSecurityBullet('End-to-End Encryption', 'X25519 Double Ratchet + AES-256-GCM'),
                  _buildSecurityBullet('Key Storage', 'Hardware Keystore / iOS Keychain'),
                  _buildSecurityBullet('Cloud Privacy', 'Zero Plaintext • Zero Logs • Spark Free'),
                  _buildSecurityBullet('Screen Shield', 'FLAG_SECURE Active (Anti-screenshot)'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Account & Connect Info Section
            _buildSectionHeader('PROFILE & CONNECT CODE', isDark),
            _buildCard(
              isDark,
              children: [
                // Connect Code Tile
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.tag_rounded, size: 18, color: isDark ? MetricColors.textPrimary : Colors.black87),
                              const SizedBox(width: 8),
                              Text('My Permanent Connect Code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isDark ? MetricColors.textPrimary : Colors.black87)),
                            ],
                          ),
                          if (_connectCode != null)
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              tooltip: 'Copy Connect Code',
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _connectCode!));
                                HapticFeedback.selectionClick();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Connect Code copied to clipboard'), duration: Duration(seconds: 1)),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _connectCode ?? 'Generating...',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.0,
                          color: isDark ? MetricColors.textPrimary : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Share this permanent 6-digit code with contacts so they can add you.',
                        style: TextStyle(fontSize: 11, color: isDark ? MetricColors.textMuted : AppColors.textMutedLight),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),

                // My Device UID
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.fingerprint_rounded, size: 18, color: isDark ? MetricColors.textSecondary : Colors.black54),
                              const SizedBox(width: 8),
                              const Text('My Device ID', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            tooltip: 'Copy My ID',
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _deviceUid));
                              HapticFeedback.selectionClick();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('My Device ID copied to clipboard'), duration: Duration(seconds: 1)),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _deviceUid,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isDark ? MetricColors.textPrimary : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Speak out or match this ID with your peer to confirm your identity.',
                        style: TextStyle(fontSize: 11, color: isDark ? MetricColors.textMuted : AppColors.textMutedLight),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),

                // Connected Peer UID
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person_pin_rounded,
                                size: 18,
                                color: _isPaired ? AppColors.secureGreen : AppColors.warningAmber,
                              ),
                              const SizedBox(width: 8),
                              const Text('Connected Peer ID', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                          if (_peerUid != null)
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              tooltip: 'Copy Peer ID',
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _peerUid!));
                                HapticFeedback.selectionClick();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Peer Device ID copied to clipboard'), duration: Duration(seconds: 1)),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _peerUid ?? 'No peer connected yet',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: _isPaired ? FontWeight.bold : FontWeight.normal,
                          color: _isPaired ? AppColors.secureGreen : (isDark ? MetricColors.textMuted : AppColors.textMutedLight),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isPaired
                            ? 'Your peer\'s "My Device ID" MUST match this exact value.'
                            : 'Once paired, your peer\'s cryptographic device ID will appear here.',
                        style: TextStyle(fontSize: 11, color: isDark ? MetricColors.textMuted : AppColors.textMutedLight),
                      ),
                    ],
                  ),
                ),

                // 12-Digit Safety Number Card (if paired)
                if (_isPaired && _safetyNumber != null) ...[
                  Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0x1810B981) : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x4010B981)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shield_rounded, size: 16, color: AppColors.secureGreen),
                              SizedBox(width: 6),
                              Text(
                                '12-DIGIT SAFETY NUMBER',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: AppColors.secureGreen,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _safetyNumber!,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3.0,
                              fontFamily: 'monospace',
                              color: AppColors.secureGreen,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Read these 12 digits aloud to your partner. If the digits on their screen match yours, you are 100% verified with zero man-in-the-middle.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: isDark ? MetricColors.textMuted : AppColors.textMutedLight),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              HapticFeedback.mediumImpact();
                              final next = !_isSafetyVerified;
                              await SecureKeyStorage.setSafetyNumberVerified(next);
                              setState(() => _isSafetyVerified = next);
                            },
                            icon: Icon(
                              _isSafetyVerified ? Icons.check_circle_rounded : Icons.verified_outlined,
                              size: 18,
                              color: _isSafetyVerified ? AppColors.secureGreen : (isDark ? MetricColors.textPrimary : Colors.black87),
                            ),
                            label: Text(
                              _isSafetyVerified ? 'Connection Verified ✓' : 'Mark as Verified Partner',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isSafetyVerified ? AppColors.secureGreen : (isDark ? MetricColors.textPrimary : Colors.black87),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _isSafetyVerified ? AppColors.secureGreen : (isDark ? MetricGlass.border : Colors.grey.shade300),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Reset / Unpair Button
                if (_isPaired) ...[
                  Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                  ListTile(
                    leading: const Icon(Icons.link_off_rounded, color: AppColors.alertRed),
                    title: const Text('Reset & Unpair Connection', style: TextStyle(color: AppColors.alertRed, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Clear shared keys and unpair from current peer'),
                    onTap: _showUnpairDialog,
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // Security & App Lock
            _buildSectionHeader('SECURITY & APP LOCK', isDark),
            _buildCard(
              isDark,
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.notifications_outlined, color: isDark ? MetricColors.textPrimary : Colors.black87),
                  title: const Text('Decoy Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Discreet calC alerts when new messages arrive'),
                  value: _notificationsEnabled,
                  activeThumbColor: isDark ? Colors.white : Colors.black,
                  activeTrackColor: isDark ? Colors.white38 : Colors.black26,
                  onChanged: (val) async {
                    await SecureKeyStorage.setNotificationsEnabled(val);
                    setState(() => _notificationsEnabled = val);
                    if (val) {
                      await DecoyNotificationService.instance.requestPermission();
                    } else {
                      await DecoyNotificationService.instance.cancelAll();
                    }
                  },
                ),
                Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                SwitchListTile(
                  secondary: Icon(Icons.lock_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87),
                  title: const Text('Biometric App Lock', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Require Face ID / Fingerprint to open'),
                  value: _biometricsEnabled,
                  activeThumbColor: isDark ? Colors.white : Colors.black,
                  activeTrackColor: isDark ? Colors.white38 : Colors.black26,
                  onChanged: (val) async {
                    await SecureKeyStorage.setBiometricsEnabled(val);
                    setState(() => _biometricsEnabled = val);
                  },
                ),
                Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                ListTile(
                  leading: Icon(Icons.timer_outlined, color: isDark ? MetricColors.textSecondary : Colors.black54),
                  title: const Text('Auto-Lock Delay', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_autoLockSeconds == 0 ? 'Immediately' : '$_autoLockSeconds seconds'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showAutoLockDialog,
                ),
                Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                ListTile(
                  leading: Icon(Icons.dialpad_rounded, color: isDark ? MetricColors.textSecondary : Colors.black54),
                  title: const Text('Secret Knock Combination', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Custom tap sequence to open vault'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SecretKnockScreen()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Account & Zero-Knowledge Recovery
            _buildSectionHeader('ACCOUNT & RECOVERY', isDark),
            _buildCard(
              isDark,
              children: [
                ListTile(
                  leading: Icon(Icons.account_circle_outlined, color: isDark ? MetricColors.textPrimary : Colors.black87),
                  title: Text(
                    _accountUsername != null ? 'Account: @$_accountUsername' : 'No Account Configured',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _isAccountLoggedIn
                        ? 'Logged in • Active session'
                        : 'Tap to log in or create account',
                  ),
                  trailing: Icon(
                    _isAccountLoggedIn ? Icons.info_outline_rounded : Icons.chevron_right_rounded,
                  ),
                  onTap: () {
                    if (_isAccountLoggedIn) {
                      _showAccountInfoDialog();
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WelcomeAuthScreen(
                            onAuthSuccess: () {
                              Navigator.pop(context);
                              _loadSettings();
                            },
                          ),
                        ),
                      );
                    }
                  },
                ),
                Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                ListTile(
                  leading: Icon(Icons.key_rounded, color: isDark ? MetricColors.textSecondary : Colors.black54),
                  title: const Text('Reset Password with Recovery Code', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Zero-knowledge account recovery flow'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ForgotPasswordScreen(
                          initialUsername: _accountUsername,
                        ),
                      ),
                    );
                  },
                ),
                if (_isAccountLoggedIn) ...[
                  Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: AppColors.alertRed),
                    title: const Text('Log Out Account', style: TextStyle(color: AppColors.alertRed, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Sign out, clear connect code & Drive backup'),
                    onTap: _handleLogout,
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // Cloud Sync & Storage
            _buildSectionHeader('CLOUD BACKUP & STORAGE (GOOGLE DRIVE)', isDark),
            _buildCard(
              isDark,
              children: [
                if (!_isOwnerDevice) ...[
                  ListTile(
                    leading: Icon(Icons.shield_outlined, color: isDark ? MetricColors.textMuted : AppColors.textMutedDark),
                    title: const Text('Peer Device Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Cloud backups are managed exclusively by the owner device.'),
                  ),
                ] else ...[
                  SwitchListTile(
                    secondary: Icon(Icons.cloud_sync_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87),
                    title: const Text('Encrypted Google Drive Backup', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Zero-knowledge ciphertext sync to owner\'s Drive'),
                    value: _driveBackupEnabled,
                    activeThumbColor: isDark ? Colors.white : Colors.black,
                    activeTrackColor: isDark ? Colors.white38 : Colors.black26,
                    onChanged: (val) async {
                      await SecureKeyStorage.setDriveBackupEnabled(val);
                      setState(() => _driveBackupEnabled = val);
                      if (val && _driveEmail == null) {
                        final result = await GoogleDriveBackupService.instance.signIn();
                        if (!mounted || !context.mounted) return;
                        if (result.success) {
                          _loadSettings();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Connected to Google Drive successfully!')),
                          );
                        } else if (result.isDeveloperError) {
                          _showGoogleSignInConfigDialog();
                        } else if (result.errorMessage != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result.errorMessage!),
                              backgroundColor: AppColors.alertRed,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _driveEmail != null ? Icons.account_circle_rounded : Icons.account_circle_outlined,
                                  size: 18,
                                  color: _driveEmail != null ? AppColors.secureGreen : (isDark ? MetricColors.textMuted : AppColors.textMutedDark),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _driveEmail ?? 'Google Account Not Connected',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ],
                            ),
                            if (_driveEmail != null)
                              TextButton(
                                onPressed: () async {
                                  await GoogleDriveBackupService.instance.signOut();
                                  _loadSettings();
                                },
                                child: const Text('Disconnect', style: TextStyle(color: AppColors.alertRed, fontSize: 12)),
                              )
                            else
                              OutlinedButton(
                                onPressed: () async {
                                  final result = await GoogleDriveBackupService.instance.signIn();
                                  if (!mounted || !context.mounted) return;
                                  if (result.success) {
                                    _loadSettings();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Connected to Google Drive successfully!')),
                                    );
                                  } else if (result.isDeveloperError) {
                                    _showGoogleSignInConfigDialog();
                                  } else if (result.errorMessage != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(result.errorMessage!),
                                        backgroundColor: AppColors.alertRed,
                                        duration: const Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  side: BorderSide(color: isDark ? MetricGlass.border : Colors.grey.shade300),
                                ),
                                child: const Text('Connect', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (_isSyncing)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? Colors.white : Colors.black),
                                ),
                              ),
                            Text(
                              _isSyncing
                                  ? 'Sync in progress...'
                                  : 'Status: ${_syncStatus ?? (_lastSyncTime != null ? "Up to date" : "Idle")}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isSyncing ? (isDark ? Colors.white : Colors.black) : AppColors.secureGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _lastSyncTime != null
                              ? 'Last synced: ${DateFormat('MMM d, yyyy • h:mm a').format(DateTime.fromMillisecondsSinceEpoch(_lastSyncTime!))}'
                              : 'Never backed up yet',
                          style: TextStyle(fontSize: 11, color: isDark ? MetricColors.textMuted : AppColors.textMutedLight),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isSyncing
                                    ? null
                                    : () async {
                                        HapticFeedback.lightImpact();
                                        await GoogleDriveBackupService.instance.syncIncremental();
                                        _loadSettings();
                                      },
                                icon: const Icon(Icons.sync_rounded, size: 16),
                                label: const Text('Back Up Now'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isDark ? MetricGlass.level1 : Colors.grey.shade100,
                                  side: BorderSide(color: isDark ? MetricGlass.border : Colors.grey.shade300),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showRestoreDialog,
                                icon: const Icon(Icons.cloud_download_rounded, size: 16),
                                label: const Text('Restore'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isDark ? MetricGlass.level1 : Colors.grey.shade100,
                                  side: BorderSide(color: isDark ? MetricGlass.border : Colors.grey.shade300),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                Divider(height: 1, color: isDark ? MetricGlass.border : Colors.grey.shade300),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: AppColors.alertRed),
                  title: const Text('Clear Decrypted Local Cache', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Purges decrypted message store on this device'),
                  onTap: _clearCache,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRestoreDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Google Drive?'),
        content: const Text(
          'This will download your latest encrypted database snapshot and media from Google Drive and decrypt them locally using your on-device keys.\n\nOnly the owner\'s device can perform this restore.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Connecting to Drive and decrypting snapshot...')),
                );
                final count = await GoogleDriveBackupService.instance.restoreFromDrive();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Successfully restored $count items from Google Drive!'),
                      backgroundColor: AppColors.secureGreen,
                    ),
                  );
                  _loadSettings();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Restore error: $e'), backgroundColor: AppColors.alertRed),
                  );
                }
              }
            },
            icon: const Icon(Icons.cloud_download_rounded, size: 18),
            label: const Text('Restore Now'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: isDark ? MetricColors.textMuted : AppColors.textMutedLight,
        ),
      ),
    );
  }

  Widget _buildCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? MetricGlass.level1 : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildSecurityBullet(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
