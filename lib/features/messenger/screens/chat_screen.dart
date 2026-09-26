import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/privacy_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/chat_provider.dart';
import '../../gallery/screens/shared_gallery_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Enable OS-level screen protection (anti-screenshot FLAG_SECURE)
    PrivacyGuard.setScreenProtection(true);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    PrivacyGuard.setScreenProtection(false);
    super.dispose();
  }

  void _sendMessage({String? mediaType}) {
    final text = _textController.text.trim();
    if (text.isEmpty && mediaType == null) return;

    HapticFeedback.lightImpact();
    ref.read(chatProvider.notifier).sendMessage(text, mediaType: mediaType);
    _textController.clear();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showReactionSheet(LocalChatMessage message) {
    HapticFeedback.mediumImpact();
    final emojis = ['❤️', '👍', '😂', '😮', '😢', '🔥'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2235) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: emojis.map((e) {
                  return InkWell(
                    onTap: () {
                      ref.read(chatProvider.notifier).setReaction(message.id, e);
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                }).toList(),
              ),
              const Divider(height: 20),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  ref.read(chatProvider.notifier).setReplyingTo(message);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.alertRed),
                title: const Text('Delete for both devices', style: TextStyle(color: AppColors.alertRed)),
                onTap: () {
                  ref.read(chatProvider.notifier).deleteMessage(message.id);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTimerDialog() {
    final current = ref.read(chatProvider).disappearingSeconds;
    final options = [
      {'label': 'Off (Keep Forever)', 'seconds': 0},
      {'label': '24 Hours', 'seconds': 86400},
      {'label': '7 Days', 'seconds': 604800},
      {'label': '30 Days', 'seconds': 2592000},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Disappearing Messages'),
        children: options.map((opt) {
          final s = opt['seconds'] as int;
          return SimpleDialogOption(
            onPressed: () {
              ref.read(chatProvider.notifier).setDisappearingTimer(s);
              Navigator.pop(ctx);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(opt['label'] as String),
                if (current == s) const Icon(Icons.check_rounded, color: AppColors.primary, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(chatProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.secureGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signal E2E Vault',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                Text(
                  'Pair-Locked • Double Ratchet',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Disappearing Messages Timer indicator
          IconButton(
            icon: Icon(
              state.disappearingSeconds > 0 ? Icons.timer_rounded : Icons.timer_outlined,
              color: state.disappearingSeconds > 0 ? AppColors.primary : null,
              size: 20,
            ),
            tooltip: 'Disappearing Timer',
            onPressed: _showTimerDialog,
          ),
          // Shared Gallery
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, size: 20),
            tooltip: 'Shared Vault Gallery',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SharedGalleryScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Security Guarantee Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? const Color(0xFF161B2E) : const Color(0xFFEEF4FF),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    state.disappearingSeconds > 0
                        ? 'Disappearing messages: ${state.disappearingSeconds ~/ 86400}d timer active'
                        : 'Encrypted end-to-end. Server holds 0 plaintext.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                    ),
                  ),
                ],
              ),
            ),

            // Messages List
            Expanded(
              child: state.messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          const Text(
                            'Channel ready for private exchange.',
                            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        final msg = state.messages[index];
                        return _buildMessageBubble(msg, isDark);
                      },
                    ),
            ),

            // Replying to banner
            if (state.replyingTo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isDark ? const Color(0xFF1E2235) : const Color(0xFFF1F5F9),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying: ${state.replyingTo!.text}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => ref.read(chatProvider.notifier).setReplyingTo(null),
                    ),
                  ],
                ),
              ),

            // Chat Input Bar
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(LocalChatMessage msg, bool isDark) {
    final isMe = msg.isMe;
    final timeStr = DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showReactionSheet(msg),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppColors.primary
                        : (isDark ? const Color(0xFF262A3D) : const Color(0xFFE9ECEF)),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Media simulation preview
                      if (msg.mediaType != null) ...[
                        Container(
                          height: 120,
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(
                              msg.mediaType == 'photo'
                                  ? Icons.photo_rounded
                                  : (msg.mediaType == 'video' ? Icons.videocam_rounded : Icons.mic_rounded),
                              size: 36,
                              color: isMe ? Colors.white : Colors.blueGrey,
                            ),
                          ),
                        ),
                      ],
                      Text(
                        msg.text,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          color: isMe
                              ? Colors.white
                              : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe
                                  ? Colors.white.withOpacity(0.7)
                                  : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                            ),
                          ),
                          if (msg.expiresAt != null) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.timer_outlined,
                              size: 10,
                              color: isMe ? Colors.white70 : Colors.grey,
                            ),
                          ],
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.done_all_rounded, size: 12, color: Colors.white70),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Reaction Bubble Badge
                if (msg.reaction != null)
                  Positioned(
                    bottom: -8,
                    right: isMe ? null : -6,
                    left: isMe ? -6 : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2235) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Text(msg.reaction!, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
          ),
        ),
      ),
      child: Row(
        children: [
          // Attachment options
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 26, color: AppColors.primary),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Wrap(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.photo_camera_rounded, color: AppColors.blueIcon),
                        title: const Text('Send Encrypted Photo (EXIF Stripped)'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _sendMessage(mediaType: 'photo');
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.videocam_rounded, color: AppColors.purpleIcon),
                        title: const Text('Send Encrypted Video'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _sendMessage(mediaType: 'video');
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.mic_rounded, color: AppColors.roseIcon),
                        title: const Text('Send Voice Note'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _sendMessage(mediaType: 'voice');
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2235) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _textController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'E2E Encrypted message...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _sendMessage(),
          ),
        ],
      ),
    );
  }
}
