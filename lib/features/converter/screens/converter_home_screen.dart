import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../models/unit_category.dart';
import '../providers/converter_provider.dart';
import 'unit_detail_screen.dart';
import 'conversion_history_screen.dart';
import 'favorites_screen.dart';
import 'converter_settings_screen.dart';
import '../../auth/auth.dart';
import '../../messenger/screens/chat_list_home_screen.dart';
import '../../../core/security/secure_key_storage.dart';

class ConverterHomeScreen extends ConsumerStatefulWidget {
  const ConverterHomeScreen({super.key});

  @override
  ConsumerState<ConverterHomeScreen> createState() => _ConverterHomeScreenState();
}

class _ConverterHomeScreenState extends ConsumerState<ConverterHomeScreen> {
  int _currentTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final List<String> _knockSequence = [];
  Timer? _knockResetTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _knockResetTimer?.cancel();
    super.dispose();
  }

  void _registerKnockTap(String categoryId) async {
    HapticFeedback.lightImpact();

    _knockSequence.add(categoryId);

    // Reset buffer after 3.5 seconds of inactivity
    _knockResetTimer?.cancel();
    _knockResetTimer = Timer(const Duration(milliseconds: 3500), () {
      _knockSequence.clear();
    });

    final targetSequence = await SecureKeyStorage.getSecretKnockSequence();

    // Check if the current knock buffer ends with the secret combination
    if (_knockSequence.length >= targetSequence.length) {
      final sublist = _knockSequence.sublist(_knockSequence.length - targetSequence.length);
      bool isMatch = true;
      for (int i = 0; i < targetSequence.length; i++) {
        if (sublist[i] != targetSequence[i]) {
          isMatch = false;
          break;
        }
      }

      if (isMatch) {
        _knockResetTimer?.cancel();
        _knockSequence.clear();
        _openSecretVault();
      }
    }
  }

  void _onCategoryTap(UnitCategory category) {
    HapticFeedback.selectionClick();
    _registerKnockTap(category.id);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => UnitDetailScreen(category: category)),
    );
  }

  /// Discrete access to the 1-to-1 End-to-End Encrypted Vault:
  /// Triggered exclusively by the secret knock combination
  Future<void> _openSecretVault() async {
    HapticFeedback.heavyImpact();
    _knockResetTimer?.cancel();
    _knockSequence.clear();

    final isLoggedIn = await AccountAuthService.isLoggedIn();
    if (!mounted) return;

    if (!isLoggedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WelcomeAuthScreen(
            onAuthSuccess: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const ChatListHomeScreen()),
                (route) => route.isFirst,
              );
            },
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ChatListHomeScreen()),
      );
    }

    // When user returns/hits back to normal metric app,
    // clear knock sequence so they must enter the knock combination again!
    if (mounted) {
      setState(() {
        _knockResetTimer?.cancel();
        _knockSequence.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget body;
    switch (_currentTabIndex) {
      case 1:
        body = const ConversionHistoryScreen();
        break;
      case 2:
        body = const FavoritesScreen();
        break;
      case 0:
      default:
        body = _buildHomeContent(isDark);
        break;
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: body,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              width: 1.0,
            ),
          ),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          currentIndex: _currentTabIndex,
          onTap: (index) {
            HapticFeedback.selectionClick();
            setState(() => _currentTabIndex = index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.schedule_rounded),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.star_rounded),
              label: 'Favorites',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent(bool isDark) {
    final categories = ref.watch(filteredCategoriesProvider);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // App Header - 100% normal decoy unit converter header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPress: _openSecretVault,
                      child: Text(
                        'Unit Converter',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Quick. Accurate. Everyday.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 24),
                  tooltip: 'Settings',
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ConverterSettingsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // Search Bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level1 : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
                  width: 1.0,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => ref.read(searchQueryProvider.notifier).setQuery(val),
                decoration: InputDecoration(
                  hintText: 'Search conversions...',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(searchQueryProvider.notifier).setQuery('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ),

        // Hero "Convert Everything" Card
        if (_searchController.text.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: _buildHeroCard(isDark),
            ),
          ),

        // 2-Column Category Grid
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              mainAxisExtent: 88,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final category = categories[index];
                return _buildCategoryCard(category, isDark);
              },
              childCount: categories.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(bool isDark) {
    return Container(
      height: 168,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? MetricGlass.level1 : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          // Left text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Convert\nEverything',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Length, weight, temperature\nand more — all in one place.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Right 3D Calculator illustration & Floating Pills
          SizedBox(
            width: 104,
            height: 124,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Neutral Dark Calculator card
                Container(
                  width: 72,
                  height: 98,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161616) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? MetricGlass.border : Colors.grey.shade300,
                      width: 1.0,
                    ),
                  ),
                  padding: const EdgeInsets.all(7),
                  child: Column(
                    children: [
                      // Screen
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.25)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Buttons Grid
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: 3,
                          mainAxisSpacing: 3,
                          crossAxisSpacing: 3,
                          physics: const NeverScrollableScrollPhysics(),
                          children: List.generate(9, (i) {
                            return Container(
                              decoration: BoxDecoration(
                                color: i == 7
                                    ? Colors.amber[400]
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.85)
                                        : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(3),
                                border: isDark
                                    ? null
                                    : Border.all(color: Colors.grey.shade300, width: 0.5),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),

                // Floating Tag: kg
                Positioned(
                  top: 2,
                  left: 0,
                  child: _buildFloatingTag('kg', isDark),
                ),

                // Floating Tag: m
                Positioned(
                  top: 4,
                  right: 0,
                  child: _buildFloatingTag('m', isDark),
                ),

                // Floating Tag: °C
                Positioned(
                  bottom: 2,
                  right: 0,
                  child: _buildFloatingTag('°C', isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingTag(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? MetricGlass.border : Colors.grey.shade300,
          width: 1.0,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDark ? MetricColors.textPrimary : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildCategoryCard(UnitCategory category, bool isDark) {
    return Material(
      color: isDark ? MetricGlass.level1 : AppColors.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => _onCategoryTap(category),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Icon Badge with dedicated Secret Knock tap interceptor
              GestureDetector(
                onTap: () => _registerKnockTap(category.id),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: category.getBadgeColor(isDark),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    category.icon,
                    color: category.iconColor,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name and Subtitle
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Chevron Arrow
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDark ? const Color(0xFF4B5563) : const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
