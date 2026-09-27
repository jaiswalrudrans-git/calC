import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/backup/google_drive_backup_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../pairing/screens/pairing_screen.dart';
import 'secret_knock_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricsEnabled = true;
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

    if (mounted) {
      setState(() {
        _biometricsEnabled = bio;
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
                  const Icon(Icons.check_rounded, color: AppColors.primary, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
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
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E2845), const Color(0xFF161F38)]
                      : [const Color(0xFFEEF3FF), const Color(0xFFE0ECFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C3B63) : const Color(0xFFD6E4FF),
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
                          color: AppColors.primary.withAlpha(38),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Signal Protocol Engine',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  _buildSecurityBullet('End-to-End Encryption', 'X25519 Double Ratchet + AES-256-GCM'),
                  _buildSecurityBullet('Key Storage', 'Hardware Keystore / iOS Keychain'),
                  _buildSecurityBullet('Cloud Privacy', 'Zero Plaintext • Zero Logs • Spark Free'),
                  _buildSecurityBullet('Screen Shield', 'FLAG_SECURE Active (Anti-screenshot)'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Pairing & Verification Section
            _buildSectionHeader('PAIRING & IDENTITY VERIFICATION', isDark),
            _buildCard(
              isDark,
              children: [
                // Pair / Re-pair Tile
                ListTile(
                  leading: const Icon(Icons.phonelink_ring_rounded, color: AppColors.primary),
                  title: const Text('Pair with Partner Device', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_isPaired ? 'Paired • Tap to view code or re-pair' : 'Exchange keys with your partner'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PairingScreen()),
                    ).then((_) => _loadSettings());
                  },
                ),
                const Divider(height: 1),

                // My Device UID
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.fingerprint_rounded, size: 18, color: AppColors.tealIcon),
                              SizedBox(width: 8),
                              Text('My Device ID', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
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
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Speak out or match this ID with your peer to confirm your identity.',
                        style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

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
                          color: _isPaired ? AppColors.secureGreen : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isPaired
                            ? 'Your peer\'s "My Device ID" MUST match this exact value.'
                            : 'Once paired, your peer\'s cryptographic device ID will appear here.',
                        style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                      ),
                    ],
                  ),
                ),

                // 12-Digit Safety Number Card (if paired)
                if (_isPaired && _safetyNumber != null) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF132A22) : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.secureGreen.withValues(alpha: 0.4)),
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
                            style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              HapticFeedback.mediumImpact();
                              final next = !_isSafetyVerified;
                              await SecureKeyStorage.setSafetyNumberVerified(next);
                              setState(() => _isSafetyVerified = next);
                            },
                            icon: Icon(
                              _isSafetyVerified ? Icons.check_circle_rounded : Icons.verified_outlined,
                              size: 18,
                              color: _isSafetyVerified ? AppColors.secureGreen : null,
                            ),
                            label: Text(
                              _isSafetyVerified ? 'Connection Verified ✓' : 'Mark as Verified Partner',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isSafetyVerified ? AppColors.secureGreen : null,
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
                  const Divider(height: 1),
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
                  secondary: const Icon(Icons.lock_rounded, color: AppColors.primary),
                  title: const Text('Biometric App Lock', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Require Face ID / Fingerprint to open'),
                  value: _biometricsEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) async {
                    await SecureKeyStorage.setBiometricsEnabled(val);
                    setState(() => _biometricsEnabled = val);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: AppColors.purpleIcon),
                  title: const Text('Auto-Lock Delay', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_autoLockSeconds == 0 ? 'Immediately' : '$_autoLockSeconds seconds'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showAutoLockDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dialpad_rounded, color: AppColors.amberIcon),
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

            // Cloud Sync & Storage
            _buildSectionHeader('CLOUD BACKUP & STORAGE (GOOGLE DRIVE)', isDark),
            _buildCard(
              isDark,
              children: [
                if (!_isOwnerDevice) ...[
                  const ListTile(
                    leading: Icon(Icons.shield_outlined, color: AppColors.textMutedDark),
                    title: Text('Peer Device Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Cloud backups are managed exclusively by the owner device.'),
                  ),
                ] else ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.cloud_sync_rounded, color: AppColors.cyanIcon),
                    title: const Text('Encrypted Google Drive Backup', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Zero-knowledge ciphertext sync to owner\'s Drive'),
                    value: _driveBackupEnabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: (val) async {
                      await SecureKeyStorage.setDriveBackupEnabled(val);
                      setState(() => _driveBackupEnabled = val);
                      if (val && _driveEmail == null) {
                        final ok = await GoogleDriveBackupService.instance.signIn();
                        if (ok) _loadSettings();
                      }
                    },
                  ),
                  const Divider(height: 1),
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
                                  color: _driveEmail != null ? AppColors.secureGreen : AppColors.textMutedDark,
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
                              FilledButton.tonal(
                                onPressed: () async {
                                  final ok = await GoogleDriveBackupService.instance.signIn();
                                  if (ok) _loadSettings();
                                },
                                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                child: const Text('Connect', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (_isSyncing)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                ),
                              ),
                            Text(
                              _isSyncing
                                  ? 'Sync in progress...'
                                  : 'Status: ${_syncStatus ?? (_lastSyncTime != null ? "Up to date" : "Idle")}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isSyncing ? AppColors.primary : AppColors.secureGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _lastSyncTime != null
                              ? 'Last synced: ${DateFormat('MMM d, yyyy • h:mm a').format(DateTime.fromMillisecondsSinceEpoch(_lastSyncTime!))}'
                              : 'Never backed up yet',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _isSyncing
                                    ? null
                                    : () async {
                                        HapticFeedback.lightImpact();
                                        await GoogleDriveBackupService.instance.syncIncremental();
                                        _loadSettings();
                                      },
                                icon: const Icon(Icons.sync_rounded, size: 16),
                                label: const Text('Back Up Now'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showRestoreDialog,
                                icon: const Icon(Icons.cloud_download_rounded, size: 16),
                                label: const Text('Restore'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1),
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
          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
        ),
      ),
    );
  }

  Widget _buildCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
          width: 1.2,
        ),
      ),
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
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
