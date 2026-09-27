import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';

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
