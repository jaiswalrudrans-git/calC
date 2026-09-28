import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

class AccountCodesDisplayScreen extends StatefulWidget {
  final String connectCode;
  final String recoveryCode;
  final VoidCallback onConfirmed;

  const AccountCodesDisplayScreen({
    super.key,
    required this.connectCode,
    required this.recoveryCode,
    required this.onConfirmed,
  });

  @override
  State<AccountCodesDisplayScreen> createState() => _AccountCodesDisplayScreenState();
}

class _AccountCodesDisplayScreenState extends State<AccountCodesDisplayScreen> {
  bool _hasSavedRecoveryCode = false;
  bool _copiedConnectCode = false;
  bool _copiedRecoveryCode = false;

  void _copyConnectCode() {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: widget.connectCode));
    setState(() => _copiedConnectCode = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('Connect code copied! Share this with contacts.'),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyRecoveryCode() {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: widget.recoveryCode));
    setState(() => _copiedRecoveryCode = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('Recovery code copied! Store it in a safe place.'),
            ),
          ],
        ),
        backgroundColor: AppColors.secureGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onProceed() {
    if (!_hasSavedRecoveryCode) return;
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // Must acknowledge recovery code before proceeding
      child: Scaffold(
        backgroundColor: isDark ? MetricColors.background : AppColors.backgroundLight,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Account Credentials'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Account Created Successfully',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? MetricColors.textPrimary : AppColors.textPrimaryLight,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Two separate codes have been generated for your account. Please review both carefully.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? MetricColors.textSecondary : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 24),

                // ============================================
                // 1. CONNECT CODE CARD (PERMANENT)
                // ============================================
                Container(
                  width: double.infinity,
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
                              Icons.people_alt_rounded,
                              color: isDark ? MetricColors.textPrimary : Colors.black87,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CONNECT CODE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: isDark ? MetricColors.textPrimary : Colors.black87,
                                  ),
                                ),
                                Text(
                                  'Permanent • Always visible in Settings',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? MetricColors.textMuted : AppColors.textMutedLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: SelectableText(
                          widget.connectCode,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4.0,
                            fontFamily: 'monospace',
                            color: isDark ? MetricColors.textPrimary : AppColors.textPrimaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Share this code with someone you want to chat with. They\'ll enter it to connect with you.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: isDark ? MetricColors.textSecondary : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _copyConnectCode,
                          icon: Icon(
                            _copiedConnectCode ? Icons.check_rounded : Icons.copy_rounded,
                            size: 15,
                            color: isDark ? MetricColors.textPrimary : Colors.black87,
                          ),
                          label: Text(
                            _copiedConnectCode ? 'Copied' : 'Copy Connect Code',
                            style: TextStyle(
                              color: isDark ? MetricColors.textPrimary : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isDark ? MetricGlass.level2 : Colors.grey.shade100,
                            side: BorderSide(
                              color: isDark ? MetricGlass.border : Colors.grey.shade300,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ============================================
                // 2. RECOVERY CODE CARD (ONE-TIME ONLY)
                // ============================================
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0x1DEF4444) : const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0x40EF4444),
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
                            decoration: const BoxDecoration(
                              color: Color(0x26EF4444),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.vpn_key_rounded, color: AppColors.alertRed, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'RECOVERY CODE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: AppColors.alertRed,
                                  ),
                                ),
                                Text(
                                  'ONE-TIME ONLY • Will NOT be shown again',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.alertRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: SelectableText(
                          widget.recoveryCode,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.5,
                            fontFamily: 'monospace',
                            color: isDark ? MetricColors.textPrimary : AppColors.textPrimaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x12EF4444) : AppColors.alertRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Save this somewhere safe. It will not be shown again. You\'ll need it if you forget your password. Without email or servers, losing both password and code means permanent lockout.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _copyRecoveryCode,
                          icon: Icon(
                            _copiedRecoveryCode ? Icons.check_rounded : Icons.copy_rounded,
                            size: 15,
                            color: AppColors.alertRed,
                          ),
                          label: Text(
                            _copiedRecoveryCode ? 'Copied' : 'Copy Recovery Code',
                            style: const TextStyle(color: AppColors.alertRed, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0x40EF4444)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // MANDATORY CONFIRMATION CHECKBOX
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? MetricGlass.level1 : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _hasSavedRecoveryCode
                          ? (isDark ? Colors.white : Colors.black)
                          : (isDark ? MetricGlass.border : AppColors.cardBorderLight),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _hasSavedRecoveryCode,
                        activeColor: isDark ? Colors.white : Colors.black,
                        checkColor: isDark ? Colors.black : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() => _hasSavedRecoveryCode = val ?? false);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _hasSavedRecoveryCode = !_hasSavedRecoveryCode);
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'I have saved my recovery code somewhere safe and understand it will not be shown again.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: isDark ? MetricColors.textPrimary : AppColors.textPrimaryLight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // PROCEED BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _hasSavedRecoveryCode ? _onProceed : null,
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
                      _hasSavedRecoveryCode ? 'Proceed to Metric →' : 'Confirm Saved to Proceed',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
