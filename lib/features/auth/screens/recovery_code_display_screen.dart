import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

class RecoveryCodeDisplayScreen extends StatefulWidget {
  final String recoveryCode;
  final bool isNewResetCode;
  final VoidCallback onConfirmed;

  const RecoveryCodeDisplayScreen({
    super.key,
    required this.recoveryCode,
    this.isNewResetCode = false,
    required this.onConfirmed,
  });

  @override
  State<RecoveryCodeDisplayScreen> createState() => _RecoveryCodeDisplayScreenState();
}

class _RecoveryCodeDisplayScreenState extends State<RecoveryCodeDisplayScreen> {
  bool _hasSavedConfirmation = false;
  bool _copied = false;

  void _copyToClipboard() {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: widget.recoveryCode));
    setState(() {
      _copied = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('Recovery code copied to clipboard!'),
            ),
          ],
        ),
        backgroundColor: AppColors.secureGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onProceed() {
    if (!_hasSavedConfirmation) return;
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // Prevent accidental back-navigation without confirmation
      child: Scaffold(
        backgroundColor: isDark ? MetricColors.background : AppColors.backgroundLight,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            widget.isNewResetCode ? 'New Recovery Key' : 'Account Recovery Key',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Security Icon Badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: isDark ? MetricGlass.level2 : Colors.grey.shade100,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? MetricGlass.borderHighlight : Colors.grey.shade300,
                      width: 1.0,
                    ),
                  ),
                  child: Icon(
                    Icons.key_rounded,
                    size: 38,
                    color: isDark ? MetricColors.textPrimary : Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  widget.isNewResetCode ? 'Your New Recovery Code' : 'Save Your Recovery Code',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? MetricColors.textPrimary : AppColors.textPrimaryLight,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),

                Text(
                  widget.isNewResetCode
                      ? 'Your previous recovery code is now invalid. Save this new code immediately to protect future account access.'
                      : 'Save this recovery code somewhere safe — you\'ll need it if you forget your password. It will not be shown again.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: isDark ? MetricColors.textSecondary : AppColors.textSecondaryLight,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // CRITICAL WARNING CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0x1DEF4444) : const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0x40EF4444),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.alertRed,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'NO EMAIL RESET AVAILABLE',
                            style: TextStyle(
                              color: AppColors.alertRed,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Metric is built with zero-knowledge privacy. We do not store your email or recover passwords. Losing both your password and this recovery code means permanent account lockout.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // RECOVERY CODE DISPLAY CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
                    color: isDark ? MetricGlass.level1 : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'RECOVERY CODE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: isDark ? MetricColors.textMuted : AppColors.textMutedLight,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SelectableText(
                        widget.recoveryCode,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.0,
                          fontFamily: 'monospace',
                          color: isDark ? MetricColors.textPrimary : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: _copyToClipboard,
                        icon: Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 16,
                          color: _copied
                              ? AppColors.secureGreen
                              : (isDark ? MetricColors.textPrimary : Colors.black87),
                        ),
                        label: Text(
                          _copied ? 'Copied to Clipboard' : 'Copy Recovery Code',
                          style: TextStyle(
                            color: _copied
                                ? AppColors.secureGreen
                                : (isDark ? MetricColors.textPrimary : Colors.black87),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isDark ? MetricGlass.level2 : Colors.grey.shade100,
                          side: BorderSide(
                            color: _copied
                                ? AppColors.secureGreen
                                : (isDark ? MetricGlass.border : Colors.grey.shade300),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // CONFIRMATION CHECKBOX
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? MetricGlass.level1 : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _hasSavedConfirmation
                          ? (isDark ? Colors.white : Colors.black)
                          : (isDark ? MetricGlass.border : AppColors.cardBorderLight),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _hasSavedConfirmation,
                        activeColor: isDark ? Colors.white : Colors.black,
                        checkColor: isDark ? Colors.black : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _hasSavedConfirmation = val ?? false;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _hasSavedConfirmation = !_hasSavedConfirmation;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'I have copied or written down this recovery code and stored it safely. I understand it will never be displayed again.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? MetricColors.textPrimary
                                    : AppColors.textPrimaryLight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // CONFIRM BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _hasSavedConfirmation ? _onProceed : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _hasSavedConfirmation ? 'I\'ve Saved It — Proceed' : 'Confirm Saved to Proceed',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
