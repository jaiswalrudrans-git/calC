import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/privacy_guard.dart';
import '../../../core/theme/app_colors.dart';

class FullScreenMediaGalleryViewer extends StatefulWidget {
  final List<LocalChatMessage> items;
  final int initialIndex;

  const FullScreenMediaGalleryViewer({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<FullScreenMediaGalleryViewer> createState() => _FullScreenMediaGalleryViewerState();
}

class _FullScreenMediaGalleryViewerState extends State<FullScreenMediaGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showOverlay = true;
  final Map<int, TransformationController> _transformControllers = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    PrivacyGuard.setScreenProtection(true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    PrivacyGuard.setScreenProtection(false);
    super.dispose();
  }

  TransformationController _getTransformController(int index) {
    if (!_transformControllers.containsKey(index)) {
      _transformControllers[index] = TransformationController();
    }
    return _transformControllers[index]!;
  }

  void _handleDoubleTap(int index, TapDownDetails details) {
    final controller = _getTransformController(index);
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
    } else {
      final position = details.localPosition;
      controller.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0)
        ..setTranslationRaw(-position.dx * 1.5, -position.dy * 1.5, 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No media items', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final currentItem = widget.items[_currentIndex];
    final timeStr = DateFormat('MMM d, yyyy • hh:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(currentItem.timestamp),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable Media PageView
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return _buildMediaPage(item, index);
            },
          ),

          // Top Header Overlay
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showOverlay ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 14,
                left: 8,
                right: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentItem.text.isNotEmpty ? currentItem.text : 'Media item',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Jump to Chat Action
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                    tooltip: 'Jump to message in Chat',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      // Pop with current message ID to jump back in chat!
                      Navigator.pop(context, currentItem.id);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Bottom Bar Overlay
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showOverlay ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: 14,
                bottom: MediaQuery.of(context).padding.bottom + 12,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Sender badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: currentItem.isMe
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      currentItem.isMe ? 'Sent by you' : 'Received',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  // Position indicator (e.g., "3 of 12")
                  Text(
                    '${_currentIndex + 1} of ${widget.items.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  // File size or jump label
                  TextButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context, currentItem.id);
                    },
                    icon: const Icon(Icons.reply_rounded, size: 16, color: Colors.white),
                    label: const Text(
                      'In Chat',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPage(LocalChatMessage item, int index) {
    final file = item.localPath != null ? File(item.localPath!) : null;
    final fileExists = file != null && file.existsSync();
    final isVideo = item.mediaType == 'video';
    TapDownDetails? tapDownDetails;

    if (isVideo) {
      return GestureDetector(
        onTap: () => setState(() => _showOverlay = !_showOverlay),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                item.text,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Encrypted Video Vault',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _showOverlay = !_showOverlay),
      onDoubleTapDown: (details) => tapDownDetails = details,
      onDoubleTap: () {
        if (tapDownDetails != null) {
          _handleDoubleTap(index, tapDownDetails!);
        }
      },
      child: SizedBox.expand(
        child: Center(
          child: InteractiveViewer(
            transformationController: _getTransformController(index),
            minScale: 1.0,
            maxScale: 4.5,
            child: fileExists
                ? Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text(
                        'Failed to load sandboxed image',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded, size: 48, color: Colors.white38),
                        SizedBox(height: 12),
                        Text(
                          'Encrypted in local vault',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
