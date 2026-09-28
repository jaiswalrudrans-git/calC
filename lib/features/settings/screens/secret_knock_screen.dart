import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../converter/models/unit_category.dart';

class SecretKnockScreen extends StatefulWidget {
  const SecretKnockScreen({super.key});

  @override
  State<SecretKnockScreen> createState() => _SecretKnockScreenState();
}

class _SecretKnockScreenState extends State<SecretKnockScreen> {
  List<String> _currentSequence = [];
  final List<String> _newSequence = [];
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSequence();
  }

  Future<void> _loadCurrentSequence() async {
    final seq = await SecureKeyStorage.getSecretKnockSequence();
    if (mounted) {
      setState(() {
        _currentSequence = seq;
      });
    }
  }

  void _onCategoryTapped(UnitCategory cat) {
    if (!_isRecording) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_newSequence.length < 8) {
        _newSequence.add(cat.id);
      }
    });
  }

  void _saveNewSequence() async {
    if (_newSequence.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 2 taps for your combination'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await SecureKeyStorage.setSecretKnockSequence(_newSequence);
    HapticFeedback.heavyImpact();

    if (mounted) {
      setState(() {
        _currentSequence = List.from(_newSequence);
        _newSequence.clear();
        _isRecording = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Secret combination updated successfully!'),
          backgroundColor: AppColors.secureGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  UnitCategory _getCategoryById(String id) {
    return UnitCatalog.categories.firstWhere(
      (c) => c.id == id,
      orElse: () => UnitCatalog.categories[0],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Secret Knock Setup'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Info Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level1 : const Color(0xFFF8F9FE),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? MetricGlass.border : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? MetricGlass.level2 : Colors.grey.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.dialpad_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Stealth Combination',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap this secret combination of cards on the Home Screen to silently open the private E2E vault. Outsiders only see a normal converter.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: isDark ? MetricColors.textMuted : AppColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // CURRENT SEQUENCE CARD
            Text(
              'CURRENT COMBINATION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: isDark ? MetricColors.textMuted : AppColors.textMutedLight,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level1 : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
                ),
              ),
              child: _currentSequence.isEmpty
                  ? Text(
                      'No combination set',
                      style: TextStyle(color: isDark ? MetricColors.textMuted : AppColors.textMutedLight),
                    )
                  : _buildSequenceChips(_currentSequence, isDark),
            ),

            const SizedBox(height: 28),

            // RECORDING / EDITING SECTION
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isRecording ? 'RECORDING NEW PATTERN' : 'SET NEW COMBINATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: _isRecording
                        ? (isDark ? MetricColors.textPrimary : Colors.black)
                        : (isDark ? MetricColors.textMuted : AppColors.textMutedLight),
                  ),
                ),
                if (_isRecording)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _newSequence.clear();
                        _isRecording = false;
                      });
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            if (!_isRecording)
              SizedBox(
                height: 52,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _isRecording = true;
                      _newSequence.clear();
                    });
                  },
                  icon: const Icon(Icons.touch_app_rounded),
                  label: const Text('Tap to Record New Sequence', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? MetricGlass.level2 : const Color(0xFFF1F5F9),
                    foregroundColor: isDark ? MetricColors.textPrimary : Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isDark ? MetricGlass.border : Colors.black12),
                    ),
                  ),
                ),
              )
            else ...[
              // Recording Buffer Display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? MetricGlass.level2 : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? MetricGlass.borderHighlight : Colors.black26,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Taps Recorded: ${_newSequence.length} / 8',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: isDark ? MetricColors.textPrimary : Colors.black87,
                          ),
                        ),
                        if (_newSequence.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.backspace_outlined, size: 18, color: isDark ? MetricColors.textSecondary : Colors.black54),
                            onPressed: () {
                              setState(() {
                                _newSequence.removeLast();
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _newSequence.isEmpty
                        ? Text(
                            'Tap the category tiles below in your desired order...',
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: isDark ? MetricColors.textMuted : AppColors.textMutedLight,
                            ),
                          )
                        : _buildSequenceChips(_newSequence, isDark),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Categories Grid for Recording
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: UnitCatalog.categories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 70,
                ),
                itemBuilder: (context, index) {
                  final cat = UnitCatalog.categories[index];
                  return Material(
                    color: isDark ? MetricGlass.level1 : AppColors.surfaceLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => _onCategoryTapped(cat),
                      borderRadius: BorderRadius.circular(14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(cat.icon, color: cat.iconColor, size: 22),
                          const SizedBox(height: 4),
                          Text(
                            cat.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? MetricColors.textPrimary : AppColors.textPrimaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Save Button
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _newSequence.length >= 2 ? _saveNewSequence : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : Colors.black,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    disabledBackgroundColor: isDark ? MetricGlass.level1 : Colors.black12,
                    disabledForegroundColor: isDark ? MetricColors.textMuted : Colors.black26,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Save Combination', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSequenceChips(List<String> sequence, bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < sequence.length; i++) ...[
          _buildChip(_getCategoryById(sequence[i]), isDark),
          if (i < sequence.length - 1)
            Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
        ],
      ],
    );
  }

  Widget _buildChip(UnitCategory cat, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cat.getBadgeColor(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cat.iconColor.withValues(alpha: isDark ? 0.4 : 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cat.icon, size: 16, color: cat.iconColor),
          const SizedBox(width: 6),
          Text(
            cat.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
