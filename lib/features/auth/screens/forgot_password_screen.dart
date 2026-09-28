import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../services/account_auth_service.dart';
import 'recovery_code_display_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialUsername;

  const ForgotPasswordScreen({
    super.key,
    this.initialUsername,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _recoveryCodeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isVerifying = false;
  bool _isResetting = false;
  bool _isVerified = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _generateNewRecoveryCode = true;

  String? _errorMessage;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername != null && widget.initialUsername!.isNotEmpty) {
      _usernameController.text = widget.initialUsername!;
      _checkLockout();
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _recoveryCodeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _checkLockout() {
    final remaining = AccountAuthService.getRemainingLockoutSeconds(_usernameController.text);
    if (remaining > 0) {
      setState(() {
        _lockoutSeconds = remaining;
      });
      _startLockoutCountdown();
    }
  }

  void _startLockoutCountdown() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = AccountAuthService.getRemainingLockoutSeconds(_usernameController.text);
      if (remaining <= 0) {
        timer.cancel();
        setState(() {
          _lockoutSeconds = 0;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _lockoutSeconds = remaining;
        });
      }
    });
  }

  Future<void> _verifyRecoveryCode() async {
    final username = _usernameController.text.trim();
    final code = _recoveryCodeController.text.trim();

    if (username.isEmpty) {
      setState(() => _errorMessage = 'Please enter your username.');
      return;
    }
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter your recovery code.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final res = await AccountAuthService.verifyRecoveryCode(
      username: username,
      recoveryCode: code,
    );

    if (!mounted) return;

    if (res.success) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isVerifying = false;
        _isVerified = true;
        _errorMessage = null;
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _isVerifying = false;
        _errorMessage = res.errorMessage;
        if (res.isLockedOut) {
          _lockoutSeconds = res.lockoutSeconds;
          _startLockoutCountdown();
        }
      });
    }
  }

  Future<void> _submitPasswordReset() async {
    final username = _usernameController.text.trim();
    final code = _recoveryCodeController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isResetting = true;
      _errorMessage = null;
    });

    final res = await AccountAuthService.resetPassword(
      username: username,
      recoveryCode: code,
      newPassword: newPassword,
      generateNewRecoveryCode: _generateNewRecoveryCode,
    );

    if (!mounted) return;

    setState(() => _isResetting = false);

    if (res.success) {
      HapticFeedback.heavyImpact();

      if (res.recoveryCode != null) {
        // Show new recovery code screen
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RecoveryCodeDisplayScreen(
              recoveryCode: res.recoveryCode!,
              isNewResetCode: true,
              onConfirmed: () {
                Navigator.pop(context); // Return to login
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Password reset! Please log in with your new password.'),
                        ),
                      ],
                    ),
                    backgroundColor: AppColors.secureGreen,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        // Pop back to login with success message
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Password reset! Please log in with your new password.'),
                ),
              ],
            ),
            backgroundColor: AppColors.secureGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _errorMessage = res.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Reset Password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Flow progress indicator
              _buildStepIndicator(isDark),
              const SizedBox(height: 24),

              if (!_isVerified)
                _buildVerificationStage(isDark)
              else
                _buildPasswordResetStage(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark) {
    return Row(
      children: [
        _buildStepDot(1, 'Verify Code', _isVerified ? true : false, !_isVerified, isDark),
        Expanded(
          child: Container(
            height: 2,
            color: _isVerified
                ? AppColors.primary
                : (isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight),
          ),
        ),
        _buildStepDot(2, 'New Password', false, _isVerified, isDark),
      ],
    );
  }

  Widget _buildStepDot(int step, String label, bool isDone, bool isActive, bool isDark) {
    final color = isDone
        ? AppColors.secureGreen
        : (isActive ? AppColors.primary : (isDark ? Colors.white24 : Colors.black26));

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDone || isActive ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '$step',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.white : color,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive || isDone ? FontWeight.w700 : FontWeight.w500,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationStage(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account Recovery',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your registered username and the 12-character recovery code saved during account setup.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 24),

        // Lockout alert banner if rate-limited
        if (_lockoutSeconds > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.alertRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.alertRed.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_clock_rounded, color: AppColors.alertRed, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Temporary Rate-Limit Lockout',
                        style: TextStyle(
                          color: AppColors.alertRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Too many failed attempts. Try again in $_lockoutSeconds seconds.',
                        style: TextStyle(
                          color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Error message banner
        if (_errorMessage != null && _lockoutSeconds == 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.alertRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.alertRed.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.alertRed, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: isDark ? Colors.red.shade200 : AppColors.alertRed,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Username Field
        Text(
          'USERNAME',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _usernameController,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'Enter username',
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
          ),
          onChanged: (_) {
            _checkLockout();
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
        ),
        const SizedBox(height: 18),

        // Recovery Code Field
        Text(
          'RECOVERY CODE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _recoveryCodeController,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            LengthLimitingTextInputFormatter(14),
            // Automatically uppercase input
            TextInputFormatter.withFunction((oldVal, newVal) {
              return newVal.copyWith(text: newVal.text.toUpperCase());
            }),
          ],
          style: TextStyle(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'XXXX-XXXX-XXXX',
            hintStyle: const TextStyle(
              letterSpacing: 1.2,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
          ),
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
        ),
        const SizedBox(height: 30),

        // Verify Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: (_lockoutSeconds > 0 || _isVerifying) ? null : _verifyRecoveryCode,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isVerifying
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                  )
                : const Text(
                    'Verify Recovery Code',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordResetStage(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Success verified badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.secureGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.secureGreen.withValues(alpha: 0.35),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.secureGreen, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recovery Code Verified',
                      style: TextStyle(
                        color: AppColors.secureGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Set a new password for future logins below.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Error message banner
        if (_errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.alertRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.alertRed.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.alertRed, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: isDark ? Colors.red.shade200 : AppColors.alertRed,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // New Password Field
        Text(
          'NEW PASSWORD',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _newPasswordController,
          obscureText: _obscureNewPassword,
          style: TextStyle(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'At least 6 characters',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNewPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
            ),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Confirm Password Field
        Text(
          'CONFIRM NEW PASSWORD',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          style: TextStyle(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'Re-enter new password',
            prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Generate New Recovery Code Recommendation Checkbox
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark.withValues(alpha: 0.5) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _generateNewRecoveryCode,
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: (val) {
                  setState(() => _generateNewRecoveryCode = val ?? true);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _generateNewRecoveryCode = !_generateNewRecoveryCode);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generate fresh recovery code (Recommended)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Replaces the used recovery code with a fresh 12-character key for future protection.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Submit Reset Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _isResetting ? null : _submitPasswordReset,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isResetting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                  )
                : const Text(
                    'Save New Password',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }
}
