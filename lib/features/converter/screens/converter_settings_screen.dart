import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../messenger/screens/chat_screen.dart';
import '../../pairing/screens/pairing_screen.dart';
import '../../settings/screens/secret_knock_screen.dart';

class ConverterSettingsScreen extends ConsumerStatefulWidget {
  const ConverterSettingsScreen({super.key});

  @override
  ConsumerState<ConverterSettingsScreen> createState() => _ConverterSettingsScreenState();
}

class _ConverterSettingsScreenState extends ConsumerState<ConverterSettingsScreen> {
  int _decimalPlaces = 4;
  bool _hapticsEnabled = true;
  bool _autoCopyEnabled = false;
  bool _useGroupingSeparators = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _decimalPlaces = prefs.getInt('calc_decimal_places') ?? 4;
          _hapticsEnabled = prefs.getBool('calc_haptics') ?? true;
          _autoCopyEnabled = prefs.getBool('calc_auto_copy') ?? false;
          _useGroupingSeparators = prefs.getBool('calc_grouping') ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _updatePreference(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is int) await prefs.setInt(key, value);
      if (value is bool) await prefs.setBool(key, value);
    } catch (_) {}
  }

  void _showDecimalDialog() {
    final options = [2, 4, 6, 8];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Decimal Places'),
        children: options.map((d) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _decimalPlaces = d);
              _updatePreference('calc_decimal_places', d);
              Navigator.pop(ctx);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$d Decimal Places (e.g. 0.${'0' * d})'),
                if (_decimalPlaces == d)
                  const Icon(Icons.check_rounded, color: AppColors.primary, size: 20),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _promptPinDialog() {
    final pinController = TextEditingController();
    String? errorMessage;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> verifyAndProceed(String enteredPin) async {
            final valid = await SecureKeyStorage.verifyPasscode(enteredPin);
            if (!valid) {
              HapticFeedback.vibrate();
              setDialogState(() {
                errorMessage = 'Incorrect PIN. Try again.';
              });
              return;
            }

            HapticFeedback.mediumImpact();
            if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            if (!mounted) return;

            _showSecurityActionsSheet();
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Text('Security PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter your 4-digit PIN to configure secret knock pattern and access vault.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8.0,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: '••••',
                    counterText: '',
                    errorText: errorMessage,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => verifyAndProceed(pinController.text),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Default PIN is 1234',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => verifyAndProceed(pinController.text),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Unlock'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSecurityActionsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Security & Knock Options',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage how you access the covert encrypted communication vault.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                ),
              ),
              const SizedBox(height: 16),

              // 1. Configure Secret Knock Pattern
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.dialpad_rounded, color: AppColors.primary),
                ),
                title: const Text('Configure Knock Pattern', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Set tap sequence on unit categories (e.g. Length → Pressure)'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SecretKnockScreen()),
                  );
                },
              ),
              const Divider(height: 1),

              // 2. Change Security PIN
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.tealIcon.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.pin_rounded, color: AppColors.tealIcon),
                ),
                title: const Text('Change Security PIN', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Change 4-digit unlock code (Current default: 1234)'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showChangePinDialog();
                },
              ),
              const Divider(height: 1),

              // 3. Open Vault Directly
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secureGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_open_rounded, color: AppColors.secureGreen),
                ),
                title: const Text('Direct Vault Access', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Open encrypted chat (or pairing screen if unpaired)'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final isPaired = await SecureKeyStorage.isPaired();
                  if (!mounted) return;

                  if (isPaired) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ChatScreen()),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PairingScreen()),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePinDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? errText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (sbCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Change Security PIN', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errText != null) ...[
                  Text(
                    errText!,
                    style: const TextStyle(color: AppColors.alertRed, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: currentCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Current PIN',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'New 4-Digit PIN',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Confirm New PIN',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final cur = currentCtrl.text.trim();
                final n = newCtrl.text.trim();
                final c = confirmCtrl.text.trim();

                final isOldValid = await SecureKeyStorage.verifyPasscode(cur);
                if (!isOldValid) {
                  setDialogState(() => errText = 'Current PIN is incorrect');
                  return;
                }
                if (n.length < 4) {
                  setDialogState(() => errText = 'New PIN must be at least 4 digits');
                  return;
                }
                if (n != c) {
                  setDialogState(() => errText = 'New PIN and Confirmation do not match');
                  return;
                }

                await SecureKeyStorage.setPasscode(n);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Security PIN successfully updated!'),
                      backgroundColor: AppColors.secureGreen,
                    ),
                  );
                }
              },
              child: const Text('Save PIN'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentThemeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Section 1: APPEARANCE & THEME
            _buildSectionHeader('APPEARANCE & THEME', isDark),
            _buildCard(
              isDark,
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System Default', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Follows operating system dark/light mode'),
                  value: ThemeMode.system,
                  groupValue: currentThemeMode,
                  activeColor: AppColors.primary,
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    }
                  },
                ),
                const Divider(height: 1),
                RadioListTile<ThemeMode>(
                  title: const Text('Light Theme', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Bright clean theme with high contrast'),
                  value: ThemeMode.light,
                  groupValue: currentThemeMode,
                  activeColor: AppColors.primary,
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    }
                  },
                ),
                const Divider(height: 1),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark Theme', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Dark OLED-friendly colors for low-light'),
                  value: ThemeMode.dark,
                  groupValue: currentThemeMode,
                  activeColor: AppColors.primary,
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Section 2: CALCULATION PREFERENCES
            _buildSectionHeader('CALCULATION PREFERENCES', isDark),
            _buildCard(
              isDark,
              children: [
                ListTile(
                  leading: const Icon(Icons.pin_outlined, color: AppColors.primary),
                  title: const Text('Decimal Places', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$_decimalPlaces decimal precision for results'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showDecimalDialog,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration_rounded, color: AppColors.purpleIcon),
                  title: const Text('Haptic Feedback', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Vibrate gently on conversion taps & actions'),
                  value: _hapticsEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() => _hapticsEnabled = val);
                    _updatePreference('calc_haptics', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.copy_all_rounded, color: AppColors.tealIcon),
                  title: const Text('Auto-Copy Results', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Automatically copy converted numbers'),
                  value: _autoCopyEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() => _autoCopyEnabled = val);
                    _updatePreference('calc_auto_copy', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.format_list_numbered_rounded, color: AppColors.amberIcon),
                  title: const Text('Thousands Separators', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Display commas in large numbers (1,000,000)'),
                  value: _useGroupingSeparators,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() => _useGroupingSeparators = val);
                    _updatePreference('calc_grouping', val);
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Section 3: ABOUT
            _buildSectionHeader('ABOUT', isDark),
            _buildCard(
              isDark,
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded, color: AppColors.cyanIcon),
                  title: const Text('Metric Unit Converter', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Version 1.2.0 • Build 2026.1'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined, color: AppColors.textMutedLight),
                  title: const Text('Precision Conversion Engine', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('High-precision scientific & everyday conversion formulas'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Section 4: APP SECURITY & KNOCK PATTERN (At the very bottom)
            _buildSectionHeader('APP ACCESS & SECURITY', isDark),
            _buildCard(
              isDark,
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                  ),
                  title: const Text('Security PIN & Knock Pattern', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Set secret pattern and access passcode (PIN required)'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _promptPinDialog,
                ),
              ],
            ),

            const SizedBox(height: 32),
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
}
