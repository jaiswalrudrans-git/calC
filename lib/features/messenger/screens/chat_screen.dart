import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/privacy_guard.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../settings/screens/settings_screen.dart';
import '../models/chat_contact.dart';
import '../providers/chat_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final ChatContact? contact;

  const ChatScreen({super.key, this.contact});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isSearching = false;
  String _searchQuery = '';
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  int _previousMessageCount = 0;
  ChatNotifier? _chatNotifier;

  @override
  void initState() {
    super.initState();
    _chatNotifier = ref.read(chatProvider.notifier);
    PrivacyGuard.setScreenProtection(true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.contact != null) {
        _chatNotifier?.setActivePeer(
          widget.contact!.uid,
          contactName: widget.contact!.username,
        );
      }
      _chatNotifier?.setChatActive(true);
    });

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _chatNotifier?.setChatActive(false);
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 60,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showSafetyNumberDialog(BuildContext context, ChatState chatState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safetyNumber = chatState.safetyNumber ?? 'Unavailable';
    final isVerified = chatState.isVerified;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isVerified ? Icons.verified_user_rounded : Icons.shield_outlined,
              color: isVerified ? AppColors.secureGreen : AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              'Safety Number',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compare this number with your contact on an independent channel to verify end-to-end encryption.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141724) : const Color(0xFFF1F4F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
                ),
              ),
              child: SelectableText(
                safetyNumber,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 17,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  isVerified ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: isVerified ? AppColors.secureGreen : AppColors.textMutedLight,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isVerified ? 'Marked as verified' : 'Not yet marked as verified',
                    style: TextStyle(
                      fontSize: 12,
                      color: isVerified ? AppColors.secureGreen : AppColors.textMutedLight,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              ref.read(chatProvider.notifier).toggleSafetyVerification();
              Navigator.pop(ctx);
            },
            icon: Icon(isVerified ? Icons.cancel_outlined : Icons.check_circle_outline),
            label: Text(isVerified ? 'Unverify' : 'Mark Verified'),
            style: FilledButton.styleFrom(
              backgroundColor: isVerified ? Colors.redAccent : AppColors.secureGreen,
            ),
          ),
        ],
      ),
    );
  }

  void _showDisappearingTimerDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final options = [
      {'label': 'Off', 'seconds': 0},
      {'label': '30 seconds', 'seconds': 30},
      {'label': '5 minutes', 'seconds': 300},
      {'label': '1 hour', 'seconds': 3600},
      {'label': '24 hours', 'seconds': 86400},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FutureBuilder<int?>(
        future: SecureKeyStorage.getDisappearingTimerSeconds(),
        builder: (fbCtx, snapshot) {
          final currentSeconds = snapshot.data ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Disappearing Messages',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map((opt) {
                  final seconds = opt['seconds'] as int;
                  final isSelected = currentSeconds == seconds;
                  return ListTile(
                    title: Text(opt['label'] as String),
                    trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
                    onTap: () async {
                      await SecureKeyStorage.setDisappearingTimerSeconds(seconds);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(seconds == 0
                                ? 'Disappearing messages turned off'
                                : 'Messages will self-destruct after ${opt['label']}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  void _onMessageLongPress(LocalChatMessage msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: AppColors.primary),
                title: const Text('Copy Text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied to clipboard')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.alertRed),
                title: const Text('Delete Message', style: TextStyle(color: AppColors.alertRed)),
                onTap: () {
                  ref.read(chatProvider.notifier).deleteMessage(msg.id);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final displayName = widget.contact?.username ??
        chatState.peerName ??
        (chatState.peerUid != null && chatState.peerUid!.length >= 8
            ? 'Peer ${chatState.peerUid!.substring(0, 6)}'
            : 'Encrypted Chat');

    // Auto-scroll on new incoming message
    if (chatState.messages.length > _previousMessageCount) {
      _previousMessageCount = chatState.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    final filteredMessages = _searchQuery.isEmpty
        ? chatState.messages
        : chatState.messages.where((m) => m.text.toLowerCase().contains(_searchQuery)).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F111A) : const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF141724) : Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Search messages...',
                  hintStyle: TextStyle(
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                  border: InputBorder.none,
                ),
              )
            : Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (chatState.isVerified)
                              const Icon(
                                Icons.verified_user_rounded,
                                color: AppColors.secureGreen,
                                size: 14,
                              ),
                          ],
                        ),
                        Text(
                          chatState.isRealtimeConnected ? 'End-to-End Encrypted' : 'Encrypted (Offline)',
                          style: TextStyle(
                            fontSize: 11,
                            color: chatState.isRealtimeConnected
                                ? AppColors.secureGreen
                                : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _isSearching ? 'Close Search' : 'Search',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
                _isSearching = !_isSearching;
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'safety') {
                _showSafetyNumberDialog(context, chatState);
              } else if (val == 'disappearing') {
                _showDisappearingTimerDialog();
              } else if (val == 'clear') {
                ref.read(chatProvider.notifier).clearAllMessages();
              } else if (val == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'safety',
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Safety Number'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'disappearing',
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Disappearing Messages'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 20, color: AppColors.alertRed),
                    SizedBox(width: 10),
                    Text('Clear Conversation', style: TextStyle(color: AppColors.alertRed)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Settings'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // E2EE Notice banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? const Color(0xFF131722) : const Color(0xFFEDF2F7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 13, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Messages are end-to-end encrypted with Signal Double Ratchet',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),

            // Messages List
            Expanded(
              child: chatState.isLoading && chatState.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : filteredMessages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 54,
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No messages found matching "$_searchQuery"'
                                    : 'No messages yet.\nSend an encrypted message to begin!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: filteredMessages.length,
                          itemBuilder: (ctx, index) {
                            final msg = filteredMessages[index];
                            return _buildMessageBubble(msg, isDark);
                          },
                        ),
            ),

            // Message Input Bar (Pure text with send button, no media buttons)
            _TextInputBar(
              isDark: isDark,
              focusNode: _inputFocusNode,
              onSend: (text) {
                ref.read(chatProvider.notifier).sendMessage(text);
                Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(LocalChatMessage msg, bool isDark) {
    final chatState = ref.watch(chatProvider);
    final isMe = (chatState.myUid.isNotEmpty)
        ? msg.senderUid == chatState.myUid
        : msg.isMe;
    final timeStr = DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp));
    final isHighlighted = msg.id == _highlightedMessageId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onLongPress: () => _onMessageLongPress(msg),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: isMe
                    ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB))
                    : (isDark ? const Color(0xFF1F2C34) : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 3),
                  bottomRight: Radius.circular(isMe ? 3 : 16),
                ),
                border: isHighlighted
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: isMe
                          ? (isDark ? Colors.white : const Color(0xFF111B21))
                          : (isDark ? Colors.white : const Color(0xFF111B21)),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white60 : Colors.black45,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        _buildStatusIndicator(msg, isDark),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(LocalChatMessage msg, bool isDark) {
    if (msg.status == 'sending') {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey),
      );
    } else if (msg.status == 'failed') {
      return GestureDetector(
        onTap: () {
          ref.read(chatProvider.notifier).retryMessage(msg.id);
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 13, color: AppColors.alertRed),
            SizedBox(width: 2),
            Text('Retry', style: TextStyle(fontSize: 10, color: AppColors.alertRed)),
          ],
        ),
      );
    } else if (msg.status == 'read') {
      return const Icon(
        Icons.done_all_rounded,
        size: 15,
        color: Color(0xFF34B7F1), // WhatsApp double blue ticks
      );
    } else if (msg.status == 'delivered') {
      return Icon(
        Icons.done_all_rounded,
        size: 15,
        color: isDark ? Colors.white54 : Colors.black45,
      );
    } else {
      return Icon(
        Icons.done_rounded,
        size: 15,
        color: isDark ? Colors.white54 : Colors.black45,
      );
    }
  }
}

/// Pure text input bar with no media buttons
class _TextInputBar extends StatefulWidget {
  final bool isDark;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;

  const _TextInputBar({
    required this.isDark,
    required this.focusNode,
    required this.onSend,
  });

  @override
  State<_TextInputBar> createState() => _TextInputBarState();
}

class _TextInputBarState extends State<_TextInputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasInputText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasInputText) {
        setState(() => _hasInputText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141724) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text Field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2436) : const Color(0xFFF1F4F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5,
                minLines: 1,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Encrypted Message...',
                  hintStyle: TextStyle(
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                    fontSize: 14,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send Button
          IconButton.filled(
            onPressed: _hasInputText ? _submit : null,
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: _hasInputText ? AppColors.primary : (isDark ? Colors.white12 : Colors.black12),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}
