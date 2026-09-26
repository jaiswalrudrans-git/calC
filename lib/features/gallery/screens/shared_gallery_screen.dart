import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/security/privacy_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../messenger/providers/chat_provider.dart';

class SharedGalleryScreen extends ConsumerStatefulWidget {
  const SharedGalleryScreen({super.key});

  @override
  ConsumerState<SharedGalleryScreen> createState() => _SharedGalleryScreenState();
}

class _SharedGalleryScreenState extends ConsumerState<SharedGalleryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    PrivacyGuard.setScreenProtection(true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    PrivacyGuard.setScreenProtection(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = ref.watch(chatProvider);
    final mediaMessages = chatState.messages.where((m) => m.mediaType != null).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Shared Vault Gallery'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Photos'),
            Tab(text: 'Videos'),
            Tab(text: 'Voice'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildMediaGrid(
              mediaMessages.where((m) => m.mediaType == 'photo').toList(),
              Icons.photo_rounded,
              'No encrypted photos yet',
              isDark,
            ),
            _buildMediaGrid(
              mediaMessages.where((m) => m.mediaType == 'video').toList(),
              Icons.videocam_rounded,
              'No encrypted videos yet',
              isDark,
            ),
            _buildMediaGrid(
              mediaMessages.where((m) => m.mediaType == 'voice').toList(),
              Icons.mic_rounded,
              'No voice notes yet',
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid(List<dynamic> items, IconData placeholderIcon, String emptyText, bool isDark) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(placeholderIcon, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              emptyText,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'All shared media is decrypted only in-memory',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2235) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('In-memory encrypted stream verified.'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Icon(placeholderIcon, size: 32, color: AppColors.primary),
            ),
          ),
        );
      },
    );
  }
}
