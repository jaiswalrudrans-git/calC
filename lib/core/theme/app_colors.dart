import 'package:flutter/material.dart';

/// Centralized Metric Color Tokens
class MetricColors {
  // Pure AMOLED foundation
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0C0C0C);

  // Neutral typography
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textMuted = Color(0xFF6E6E6E);

  // Glass borders and edges
  static const Color border = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const Color borderLight = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
}

/// Neutral Liquid Glass Opacities
class MetricGlass {
  // Level 1: Subtle surface (rgba 255,255,255, 0.035)
  static const Color level1 = Color(0x09FFFFFF);

  // Level 2: Standard glass (rgba 255,255,255, 0.065)
  static const Color level2 = Color(0x10FFFFFF);

  // Level 3: Elevated glass (rgba 255,255,255, 0.095)
  static const Color level3 = Color(0x18FFFFFF);

  // Subtle glass edge reflection
  static const Color border = Color(0x12FFFFFF); // rgba(255,255,255,0.07)
  static const Color borderHighlight = Color(0x24FFFFFF); // rgba(255,255,255,0.14)
}

/// Reserved exclusively for the Chat Message visual system.
/// Outside the chat, turquoise is never used.
class MetricChatColors {
  // Received messages
  static const Color receivedText = Color(0xFF21DCC8); // Sophisticated muted turquoise
  static const Color receivedBubble = Color(0xFF091211); // Dark translucent glass with faint turquoise presence
  static const Color receivedBorder = Color(0x2B21DCC8); // Subtle turquoise edge highlight

  // Sent messages
  static const Color sentText = Color(0xFFC5C5C5); // Neutral light grey
  static const Color sentBubble = Color(0xFF141414); // Neutral translucent glass
  static const Color sentBorder = Color(0x17FFFFFF); // Neutral edge reflection

  // Message metadata & chat actions
  static const Color readReceipt = Color(0xFF21DCC8);
  static const Color sendButton = Color(0xFF21DCC8);
  static const Color unreadDot = Color(0xFF21DCC8);
  static const Color timestamp = Color(0xFF666666);
}

/// AppColors: Full compatibility with all existing screen references,
/// re-anchored to True AMOLED Black and Neutral Liquid Glass.
class AppColors {
  // Primary & Accents: Adaptive neutral foundation
  static const Color primary = Color(0xFF0F172A); // High-contrast neutral ink for light mode default
  static const Color primaryLight = Color(0xFF0F172A); // Dark ink for light mode
  static const Color primaryDark = Color(0xFFF5F5F5); // Crisp white for dark mode
  static const Color accent = Color(0xFF888888);

  static Color primaryAdaptive(bool isDark) => isDark ? primaryDark : primaryLight;

  // True AMOLED Black Backgrounds
  static const Color backgroundLight = Color(0xFFF8F9FE);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color cardBorderLight = Color(0xFFE8ECEF);

  static const Color backgroundDark = Color(0xFF000000); // 100% True AMOLED Black
  static const Color surfaceDark = Color(0xFF0D0D0D); // Neutral deep surface
  static const Color cardBorderDark = Color(0x14FFFFFF); // Subtle 1px neutral glass edge

  // Text colors
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textMutedLight = Color(0xFF94A3B8);

  static const Color textPrimaryDark = Color(0xFFF5F5F5); // High contrast clean white
  static const Color textSecondaryDark = Color(0xFFB0B0B0); // Medium grey
  static const Color textMutedDark = Color(0xFF6E6E6E); // Muted dark grey

  // Status & Security
  static const Color secureGreen = Color(0xFF10B981);
  static const Color alertRed = Color(0xFFEF4444);
  static const Color warningAmber = Color(0xFFF59E0B);

  // Converter Category Accents (Pastel tints in Light Mode, deep subtle AMOLED tints in Dark Mode)
  static const Color blueIcon = Color(0xFF64748B);
  static const Color blueBadge = Color(0xFFF1F5F9);
  static const Color blueBadgeDark = Color(0xFF161616);

  static const Color greenIcon = Color(0xFF10B981);
  static const Color greenBadge = Color(0xFFE8F5E9);
  static const Color greenBadgeDark = Color(0xFF101C17);

  static const Color redIcon = Color(0xFFF43F5E);
  static const Color redBadge = Color(0xFFFCE4EC);
  static const Color redBadgeDark = Color(0xFF1F1214);

  static const Color amberIcon = Color(0xFFF59E0B);
  static const Color amberBadge = Color(0xFFFFF8E1);
  static const Color amberBadgeDark = Color(0xFF1C170E);

  static const Color purpleIcon = Color(0xFFA855F7);
  static const Color purpleBadge = Color(0xFFF3E5F5);
  static const Color purpleBadgeDark = Color(0xFF17111E);

  static const Color tealIcon = Color(0xFF14B8A6);
  static const Color tealBadge = Color(0xFFE0F2F1);
  static const Color tealBadgeDark = Color(0xFF0F1918);

  static const Color orangeIcon = Color(0xFFFB923C);
  static const Color orangeBadge = Color(0xFFFFF3E0);
  static const Color orangeBadgeDark = Color(0xFF1C1510);

  static const Color cyanIcon = Color(0xFF0284C7);
  static const Color cyanBadge = Color(0xFFE0F7FA);
  static const Color cyanBadgeDark = Color(0xFF11181D);

  static const Color violetIcon = Color(0xFF8B5CF6);
  static const Color violetBadge = Color(0xFFEDE7F6);
  static const Color violetBadgeDark = Color(0xFF18121F);

  static const Color roseIcon = Color(0xFFFB7185);
  static const Color roseBadge = Color(0xFFFFEBEE);
  static const Color roseBadgeDark = Color(0xFF1D1214);

  static const Color emeraldIcon = Color(0xFF059669);
  static const Color emeraldBadge = Color(0xFFE8F8F5);
  static const Color emeraldBadgeDark = Color(0xFF0E1A15);

  static const Color indigoIcon = Color(0xFF6366F1);
  static const Color indigoBadge = Color(0xFFE8EAF6);
  static const Color indigoBadgeDark = Color(0xFF14141F);
}
