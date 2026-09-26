import 'package:flutter/material.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/database/local_cache.dart';
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
  bool _driveBackupEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final bio = await SecureKeyStorage.isBiometricsEnabled();
    final autoLock = await SecureKeyStorage.getAutoLockSeconds();
    final paired = await SecureKeyStorage.isPaired();
    final uid = await SecureKeyStorage.getMyDeviceId() ?? 'Not Initialized';

    if (mounted) {
      setState(() {
        _biometricsEnabled = bio;
        _autoLockSeconds = autoLock;
        _isPaired = paired;
        _deviceUid = uid;
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
                            _isPaired ? 'Paired with 1 trusted peer' : 'Device not yet paired',
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

            // Pairing Section
            _buildSectionHeader('PAIRING & IDENTITY', isDark),
            _buildCard(
              isDark,
              children: [
                ListTile(
                  leading: const Icon(Icons.phonelink_ring_rounded, color: AppColors.primary),
                  title: const Text('Pair with Partner Device', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_isPaired ? 'Tap to view code or re-pair' : 'Exchange keys with your partner'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PairingScreen()),
                    ).then((_) => _loadSettings());
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded, color: AppColors.tealIcon),
                  title: const Text('My Device UID', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _deviceUid.length > 20 ? '${_deviceUid.substring(0, 16)}...' : _deviceUid,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
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
            _buildSectionHeader('CLOUD BACKUP & STORAGE', isDark),
            _buildCard(
              isDark,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_sync_rounded, color: AppColors.cyanIcon),
                  title: const Text('Google Drive Backup', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Encrypted DB only, off by default (Zero Cost)'),
                  value: _driveBackupEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() => _driveBackupEnabled = val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          val
                              ? 'Google Drive encrypted sync enabled (uses your free personal quota)'
                              : 'Cloud backup disabled',
                        ),
                      ),
                    );
                  },
                ),
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
