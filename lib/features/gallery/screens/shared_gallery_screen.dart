import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/privacy_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../messenger/providers/chat_provider.dart';
import 'fullscreen_media_gallery_viewer.dart';

class SharedGalleryScreen extends ConsumerStatefulWidget {
  const SharedGalleryScreen({super.key});

  @override
  ConsumerState<SharedGalleryScreen> createState() => _SharedGalleryScreenState();
}

class _SharedGalleryScreenState extends ConsumerState<SharedGalleryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingId;
  PlayerState _playerState = PlayerState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    PrivacyGuard.setScreenProtection(true);

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _playerState = state);
      }
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _currentPosition = pos);
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() => _totalDuration = dur);
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _currentlyPlayingId = null;
          _currentPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer.dispose();
    PrivacyGuard.setScreenProtection(false);
    super.dispose();
  }

  Future<void> _toggleAudioPlay(LocalChatMessage message) async {
    HapticFeedback.lightImpact();
    if (_currentlyPlayingId == message.id && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
      return;
    }

    if (_currentlyPlayingId == message.id && _playerState == PlayerState.paused) {
      await _audioPlayer.resume();
      return;
    }

    if (message.localPath == null || !File(message.localPath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio file not found in local vault')),
      );
      return;
    }

    await _audioPlayer.stop();
    setState(() {
      _currentlyPlayingId = message.id;
      _currentPosition = Duration.zero;
      _totalDuration = Duration(seconds: message.duration ?? 0);
    });

    await _audioPlayer.play(DeviceFileSource(message.localPath!));
  }

  /// Groups messages chronologically by "Month Year" (e.g. "September 2026")
  Map<String, List<LocalChatMessage>> _groupByMonth(List<LocalChatMessage> items) {
    final Map<String, List<LocalChatMessage>> grouped = {};
    final sorted = List<LocalChatMessage>.from(items)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    for (final item in sorted) {
      final date = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
      final key = DateFormat('MMMM yyyy').format(date);
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDurationSeconds(int? seconds) {
    if (seconds == null || seconds <= 0) return '0:00';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  IconData _getDocumentIcon(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
      case 'txt':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getDocumentColor(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return AppColors.alertRed;
      case 'doc':
      case 'docx':
      case 'txt':
        return AppColors.blueIcon;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return AppColors.secureGreen;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
        return AppColors.orangeIcon;
      default:
        return AppColors.purpleIcon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = ref.watch(chatProvider);

    final allMedia = chatState.messages.where((m) => m.mediaType != null).toList();
    final photosAndVideos = allMedia
        .where((m) => m.mediaType == 'image' || m.mediaType == 'video')
        .toList();
    final documents = allMedia.where((m) => m.mediaType == 'document').toList();
    final voiceNotes = allMedia.where((m) => m.mediaType == 'voice').toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Media, Links & Docs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${allMedia.length} total encrypted items',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: 'Media (${photosAndVideos.length})'),
            Tab(text: 'Docs (${documents.length})'),
            Tab(text: 'Voice (${voiceNotes.length})'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Photos & Videos
            _buildPhotosAndVideosTab(photosAndVideos, isDark),

            // Tab 2: Documents
            _buildDocumentsTab(documents, isDark),

            // Tab 3: Voice Notes
            _buildVoiceNotesTab(voiceNotes, isDark),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: PHOTOS & VIDEOS
  // ==========================================
  Widget _buildPhotosAndVideosTab(List<LocalChatMessage> items, bool isDark) {
    if (items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No Photos or Videos',
        subtitle: 'Photos and videos shared in chat will appear here encrypted in the local vault.',
        isDark: isDark,
      );
    }

    final grouped = _groupByMonth(items);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.keys.length,
      itemBuilder: (context, groupIndex) {
        final monthKey = grouped.keys.elementAt(groupIndex);
        final monthItems = grouped[monthKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            _buildSectionHeader(monthKey, monthItems.length, isDark),

            // 3-Column Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
                childAspectRatio: 1.0,
              ),
              itemCount: monthItems.length,
              itemBuilder: (gridCtx, itemIndex) {
                final item = monthItems[itemIndex];
                final file = item.localPath != null ? File(item.localPath!) : null;
                final fileExists = file != null && file.existsSync();
                final isVideo = item.mediaType == 'video';

                return InkWell(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final nav = Navigator.of(context);
                    // Open full screen gallery with swipe between all items in this section
                    final targetMessageId = await nav.push<String>(
                      MaterialPageRoute(
                        builder: (_) => FullScreenMediaGalleryViewer(
                          items: monthItems,
                          initialIndex: itemIndex,
                        ),
                      ),
                    );

                    // If user requested to jump back to message in chat, pop with ID
                    if (!mounted) return;
                    if (targetMessageId != null) {
                      nav.pop(targetMessageId);
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail
                      if (fileExists)
                        Image.file(
                          file,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: isDark ? const Color(0xFF1E2235) : const Color(0xFFE2E8F0),
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, size: 28, color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        Container(
                          color: isDark ? const Color(0xFF1E2235) : const Color(0xFFE2E8F0),
                          child: const Center(
                            child: Icon(Icons.lock_rounded, size: 28, color: AppColors.primary),
                          ),
                        ),

                      // Video Badge & Duration
                      if (isVideo)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          right: 4,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                              ),
                              if (item.duration != null && item.duration! > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _formatDurationSeconds(item.duration),
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // TAB 2: DOCUMENTS
  // ==========================================
  Widget _buildDocumentsTab(List<LocalChatMessage> items, bool isDark) {
    if (items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.insert_drive_file_outlined,
        title: 'No Documents',
        subtitle: 'PDFs, spreadsheets, text files, and archives shared in chat will appear here.',
        isDark: isDark,
      );
    }

    final grouped = _groupByMonth(items);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.keys.length,
      itemBuilder: (context, groupIndex) {
        final monthKey = grouped.keys.elementAt(groupIndex);
        final monthItems = grouped[monthKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(monthKey, monthItems.length, isDark),
            ...monthItems.map((item) {
              final date = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
              final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(date);
              final docColor = _getDocumentColor(item.text);
              final docIcon = _getDocumentIcon(item.text);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF262C40) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: docColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(docIcon, color: docColor, size: 26),
                  ),
                  title: Text(
                    item.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Text(
                          _formatFileSize(item.mediaSize),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                          ),
                        ),
                        const Text(' • '),
                        Expanded(
                          child: Text(
                            dateStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                    tooltip: 'Show in Chat',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context, item.id);
                    },
                  ),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context, item.id);
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ==========================================
  // TAB 3: VOICE NOTES
  // ==========================================
  Widget _buildVoiceNotesTab(List<LocalChatMessage> items, bool isDark) {
    if (items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.mic_none_rounded,
        title: 'No Voice Notes',
        subtitle: 'Recorded audio clips and voice messages will appear here for instant playback.',
        isDark: isDark,
      );
    }

    final grouped = _groupByMonth(items);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.keys.length,
      itemBuilder: (context, groupIndex) {
        final monthKey = grouped.keys.elementAt(groupIndex);
        final monthItems = grouped[monthKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(monthKey, monthItems.length, isDark),
            ...monthItems.map((item) {
              final isCurrent = _currentlyPlayingId == item.id;
              final isPlaying = isCurrent && _playerState == PlayerState.playing;
              final date = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
              final dateStr = DateFormat('MMM d • h:mm a').format(date);

              double progress = 0.0;
              if (isCurrent && _totalDuration.inMilliseconds > 0) {
                progress = (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0);
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCurrent
                        ? AppColors.primary
                        : (isDark ? const Color(0xFF262C40) : const Color(0xFFE2E8F0)),
                    width: isCurrent ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Play/Pause button
                        GestureDetector(
                          onTap: () => _toggleAudioPlay(item),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Title & Sender info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    item.isMe ? 'Voice Note (You)' : 'Voice Note (Peer)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: item.isMe
                                          ? AppColors.primary.withValues(alpha: 0.15)
                                          : AppColors.secureGreen.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _formatDurationSeconds(item.duration),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: item.isMe ? AppColors.primary : AppColors.secureGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Jump to Chat Action
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                          tooltip: 'Show in Chat',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(context, item.id);
                          },
                        ),
                      ],
                    ),

                    // Progress Slider
                    if (isCurrent) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: isDark ? Colors.white10 : Colors.black12,
                          color: AppColors.primary,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ==========================================
  // HELPERS
  // ==========================================
  Widget _buildSectionHeader(String title, int count, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2235) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
