import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// Performance-optimized Liquid Glass container for True AMOLED Black.
/// Levels:
/// - 1: Subtle surface (rgba 255,255,255, 0.03) for secondary items & list cards
/// - 2: Standard glass (rgba 255,255,255, 0.06) for controls, composer, navigation
/// - 3: Elevated glass (rgba 255,255,255, 0.09) for dialogs, modals, floating action bars
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final int level;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool hasBlur;
  final double blurSigma;
  final Color? customColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.level = 1,
    this.borderRadius = 18,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.hasBlur = false,
    this.blurSigma = 16,
    this.customColor,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    if (customColor != null) {
      bg = customColor!;
    } else if (isDark) {
      switch (level) {
        case 3:
          bg = MetricGlass.level3;
          break;
        case 2:
          bg = MetricGlass.level2;
          break;
        case 1:
        default:
          bg = MetricGlass.level1;
          break;
      }
    } else {
      bg = Colors.white;
    }

    final effectiveBorder = Border.all(
      color: borderColor ?? (isDark ? MetricGlass.border : AppColors.cardBorderLight),
      width: 1.0,
    );

    Widget content = Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: effectiveBorder,
      ),
      child: child,
    );

    if (hasBlur) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      );
    }

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap!();
          },
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Refined neutral glass interactive button
class LiquidGlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool isPrimary;
  final bool isLoading;

  const LiquidGlassButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    this.borderRadius = 16,
    this.isPrimary = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color borderCol;
    if (!isDark) {
      bg = isPrimary ? Colors.black : Colors.grey.shade100;
      borderCol = Colors.transparent;
    } else if (isPrimary) {
      bg = const Color(0x1AFFFFFF); // Level 3 glass (0.10)
      borderCol = const Color(0x26FFFFFF); // 0.15 border
    } else {
      bg = const Color(0x0DFFFFFF); // Level 1 glass (0.05)
      borderCol = const Color(0x14FFFFFF); // 0.08 border
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: isLoading || onPressed == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onPressed!();
              },
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderCol, width: 1.0),
          ),
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : child,
        ),
      ),
    );
  }
}

/// Liquid Glass Icon Button
class LiquidGlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final String? tooltip;

  const LiquidGlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 42,
    this.iconSize = 20,
    this.iconColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final btn = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onPressed!();
              },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? MetricGlass.level2 : Colors.grey.shade100,
            border: Border.all(
              color: isDark ? MetricGlass.border : Colors.grey.shade300,
              width: 1.0,
            ),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor ?? (isDark ? MetricColors.textPrimary : Colors.black87),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}
