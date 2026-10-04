import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/privacy_guard.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/notifications/decoy_notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../core/config/firebase_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _isNearBottom = true;
  bool _hasNewUnreadWhileScrolled = false;
  double _lastBottomInset = 0.0;

  @override
  void initState() {
    super.initState();
    _chatNotifier = ref.read(chatProvider.notifier);
    PrivacyGuard.setScreenProtection(true);

    _scrollController.addListener(_onScroll);
    _inputFocusNode.addListener(_onFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.contact != null) {
        _chatNotifier?.setActivePeer(
          widget.contact!.uid,
          contactName: widget.contact!.username,
        );
        final myUid = await SecureKeyStorage.getMyDeviceId();
        if (myUid != null && myUid.isNotEmpty) {
          final participants = [myUid, widget.contact!.uid]..sort();
          final channelId = 'ch_${participants.join('_')}';
          DecoyNotificationService.instance.setActiveConversation(channelId);
        }
      }
      _chatNotifier?.setChatActive(true);
    });

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // In reverse: true ListView, offset 0 is the bottom (latest message)
    final nearBottom = _scrollController.offset <= 100;
    if (nearBottom != _isNearBottom) {
      setState(() {
        _isNearBottom = nearBottom;
        if (nearBottom) {
          _hasNewUnreadWhileScrolled = false;
        }
      });
    }
  }

  Timer? _focusTimer;

  void _onFocusChange() {
    if (_inputFocusNode.hasFocus && _isNearBottom) {
      _focusTimer?.cancel();
      _focusTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && _isNearBottom) {
          _scrollToBottom();
        }
      });
    }
  }

  @override
  void dispose() {
    DecoyNotificationService.instance.setActiveConversation(null);
    _highlightTimer?.cancel();
    _focusTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _inputFocusNode.removeListener(_onFocusChange);
    _inputFocusNode.dispose();
    _chatNotifier?.setChatActive(false);
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (_scrollController.hasClients) {
      if (animate) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    }
    if (_hasNewUnreadWhileScrolled) {
      setState(() => _hasNewUnreadWhileScrolled = false);
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
              color: isVerified ? AppColors.secureGreen : (isDark ? Colors.white : Colors.black87),
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
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 17,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
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
                      Icon(Icons.timer_outlined, color: isDark ? Colors.white : Colors.black87),
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
                    trailing: isSelected ? Icon(Icons.check, color: isDark ? Colors.white : Colors.black87) : null,
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

  final Set<String> _selectedMessageIds = <String>{};

  bool get _isSelectionMode => _selectedMessageIds.isNotEmpty;

  void _toggleMessageSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedMessageIds.contains(id)) {
        _selectedMessageIds.remove(id);
      } else {
        _selectedMessageIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMessageIds.clear();
    });
  }

  void _onMessageLongPress(LocalChatMessage msg) {
    if (!_isSelectionMode) {
      HapticFeedback.mediumImpact();
      setState(() {
        _selectedMessageIds.add(msg.id);
      });
    } else {
      _toggleMessageSelection(msg.id);
    }
  }

  void _onMessageTap(LocalChatMessage msg) {
    if (_isSelectionMode) {
      _toggleMessageSelection(msg.id);
    }
  }

  void _copySelectedMessages(List<LocalChatMessage> messages) {
    final selectedMsgs = messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final combinedText = selectedMsgs.map((m) => m.text).join('\n');
    Clipboard.setData(ClipboardData(text: combinedText));
    final count = _selectedMessageIds.length;
    _clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(count == 1 ? 'Message copied to clipboard' : '$count messages copied')),
      );
    }
  }

  void _confirmDeleteSelected() {
    final count = _selectedMessageIds.length;
    if (count == 0) return;

    final chatState = ref.read(chatProvider);
    final myUid = chatState.myUid;
    final selectedMsgs = chatState.messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();

    // Check if any of the selected messages were sent by me
    final hasSentByMe = selectedMsgs.any(
      (m) => m.isMe || (myUid.isNotEmpty && m.senderUid == myUid),
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          count == 1 ? 'Delete message?' : 'Delete $count messages?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        content: Text(
          hasSentByMe
              ? 'You can delete for everyone or for yourself only.'
              : 'Delete message(s) from this device?',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final idsToDelete = _selectedMessageIds.toList();
              _clearSelection();
              await ref.read(chatProvider.notifier).deleteMessages(idsToDelete, forEveryone: false);
            },
            child: const Text('Delete for Me'),
          ),
          if (hasSentByMe)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final idsToDelete = _selectedMessageIds.toList();
                _clearSelection();
                await ref.read(chatProvider.notifier).deleteMessages(idsToDelete, forEveryone: true);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.alertRed),
              child: const Text('Delete for Everyone'),
            ),
        ],
      ),
    );
  }

  void _showClearChatDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear this chat?'),
        content: Text(
          'This will permanently delete all messages in this conversation.',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(chatProvider.notifier).clearAllMessages();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat cleared')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.alertRed),
            child: const Text('Clear Chat'),
          ),
        ],
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

    final activePeerUid = widget.contact?.uid ?? chatState.peerUid ?? '';

    // Handle bottom inset changes (keyboard opens/closes)
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (bottomInset > _lastBottomInset && _isNearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isNearBottom) {
          _scrollToBottom();
        }
      });
    }
    _lastBottomInset = bottomInset;

    // Auto-scroll on new incoming message only if near bottom
    if (chatState.messages.length > _previousMessageCount) {
      final isFirstLoad = _previousMessageCount == 0;
      _previousMessageCount = chatState.messages.length;
      if (!isFirstLoad) {
        if (_isNearBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        } else {
          if (!_hasNewUnreadWhileScrolled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hasNewUnreadWhileScrolled = true);
            });
          }
        }
      } else {
        // First load opens already scrolled to latest message
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
      }
    } else if (chatState.messages.length < _previousMessageCount) {
      _previousMessageCount = chatState.messages.length;
    }

    final filteredMessages = _searchQuery.isEmpty
        ? chatState.messages
        : chatState.messages.where((m) => m.text.toLowerCase().contains(_searchQuery)).toList();

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectionMode) {
          _clearSelection();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: isDark ? MetricColors.background : const Color(0xFFF6F8FC),
        appBar: _isSelectionMode
            ? AppBar(
                backgroundColor: isDark ? MetricColors.surface : Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.close_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87),
                  onPressed: _clearSelection,
                  tooltip: 'Cancel',
                ),
                title: Text(
                  '${_selectedMessageIds.length}',
                  style: TextStyle(
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.copy_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87),
                    tooltip: 'Copy',
                    onPressed: () => _copySelectedMessages(filteredMessages),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.alertRed),
                    tooltip: 'Delete',
                    onPressed: _confirmDeleteSelected,
                  ),
                  const SizedBox(width: 4),
                ],
              )
            : AppBar(
                backgroundColor: isDark ? MetricColors.background : Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                titleSpacing: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: isDark ? MetricColors.textPrimary : Colors.black87),
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
                    backgroundColor: isDark ? MetricGlass.level2 : Colors.grey.shade200,
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: isDark ? MetricColors.textPrimary : Colors.black87,
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
                        _PresenceSubtitle(peerUid: activePeerUid, isDark: isDark),
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
                _showClearChatDialog();
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              color: isDark ? MetricGlass.level1 : const Color(0xFFEDF2F7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, size: 12, color: isDark ? MetricColors.textMuted : AppColors.textSecondaryLight),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Messages are end-to-end encrypted with Signal Double Ratchet',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? MetricColors.textMuted : AppColors.textSecondaryLight,
                      ),
                      overflow: TextOverflow.ellipsis,
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
                      : Stack(
                          children: [
                            ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              itemCount: filteredMessages.length,
                              findChildIndexCallback: (Key key) {
                                if (key is ValueKey<String>) {
                                  final id = key.value;
                                  for (int i = 0; i < filteredMessages.length; i++) {
                                    if (filteredMessages[filteredMessages.length - 1 - i].id == id) {
                                      return i;
                                    }
                                  }
                                }
                                return null;
                              },
                              itemBuilder: (ctx, index) {
                                final msg = filteredMessages[filteredMessages.length - 1 - index];
                                final isMe = (chatState.myUid.isNotEmpty)
                                    ? msg.senderUid == chatState.myUid
                                    : msg.isMe;
                                final isSelected = _selectedMessageIds.contains(msg.id);
                                return _MessageBubble(
                                  key: ValueKey(msg.id),
                                  msg: msg,
                                  isDark: isDark,
                                  isMe: isMe,
                                  isSelected: isSelected,
                                  isHighlighted: msg.id == _highlightedMessageId,
                                  onTap: () => _onMessageTap(msg),
                                  onLongPress: () => _onMessageLongPress(msg),
                                  onRetry: () => ref.read(chatProvider.notifier).retryMessage(msg.id),
                                );
                              },
                            ),
                            if (!_isNearBottom)
                              Positioned(
                                bottom: 12,
                                right: 16,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(22),
                                    onTap: () => _scrollToBottom(),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: _hasNewUnreadWhileScrolled ? 14 : 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E2433) : Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: _hasNewUnreadWhileScrolled
                                              ? MetricChatColors.receivedText
                                              : (isDark ? MetricGlass.border : AppColors.cardBorderLight),
                                          width: 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.18),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.arrow_downward_rounded,
                                            size: 16,
                                            color: _hasNewUnreadWhileScrolled
                                                ? MetricChatColors.receivedText
                                                : (isDark ? MetricColors.textPrimary : Colors.black87),
                                          ),
                                          if (_hasNewUnreadWhileScrolled) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              'New message',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _hasNewUnreadWhileScrolled
                                                    ? MetricChatColors.receivedText
                                                    : (isDark ? MetricColors.textPrimary : Colors.black87),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),

            // Message Input Bar (Pure text with send button, no media buttons)
            _TextInputBar(
              isDark: isDark,
              focusNode: _inputFocusNode,
              onSend: (text) {
                ref.read(chatProvider.notifier).sendMessage(text);
                _scrollToBottom();
              },
            ),
          ],
        ),
      ),
    ),
  );
  }
}


/// Keyed, isolated message bubble wrapped in RepaintBoundary to eliminate O(N) rebuilds
class _MessageBubble extends StatelessWidget {
  final LocalChatMessage msg;
  final bool isDark;
  final bool isMe;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;

  const _MessageBubble({
    super.key,
    required this.msg,
    required this.isDark,
    required this.isMe,
    required this.isSelected,
    required this.isHighlighted,
    required this.onTap,
    required this.onLongPress,
    required this.onRetry,
  });

  static final DateFormat _timeFormatter = DateFormat('hh:mm a');

  @override
  Widget build(BuildContext context) {
    final timeStr = _timeFormatter.format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp));

    return RepaintBoundary(
      child: Container(
        color: isSelected
            ? (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0x3325D366))
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: onTap,
                onLongPress: onLongPress,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? (isDark ? MetricChatColors.sentBubble : const Color(0x80E5E7EB))
                        : (isDark ? MetricChatColors.receivedBubble : const Color(0x80FFFFFF)),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : (isHighlighted
                              ? (isDark ? Colors.white70 : Colors.black54)
                              : (isDark
                                  ? (isMe ? MetricChatColors.sentBorder : MetricChatColors.receivedBorder)
                                  : Colors.black.withValues(alpha: 0.08))),
                      width: isSelected ? 2.0 : (isHighlighted ? 1.5 : 1.0),
                    ),
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
                              ? (isDark ? MetricChatColors.sentText : const Color(0xFF111827))
                              : (isDark ? MetricChatColors.receivedText : const Color(0xFF111827)),
                          fontWeight: FontWeight.w400,
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
                              color: isDark ? MetricChatColors.timestamp : Colors.black45,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _StatusIndicator(
                              status: msg.status,
                              isDark: isDark,
                              onRetry: onRetry,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final String status;
  final bool isDark;
  final VoidCallback onRetry;

  const _StatusIndicator({
    required this.status,
    required this.isDark,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (status == 'sending') {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey),
      );
    } else if (status == 'failed') {
      return GestureDetector(
        onTap: onRetry,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 13, color: AppColors.alertRed),
            SizedBox(width: 2),
            Text('Retry', style: TextStyle(fontSize: 10, color: AppColors.alertRed)),
          ],
        ),
      );
    } else if (status == 'read') {
      return const Icon(
        Icons.done_all_rounded,
        size: 15,
        color: MetricChatColors.readReceipt,
      );
    } else if (status == 'delivered') {
      return Icon(
        Icons.done_all_rounded,
        size: 15,
        color: isDark ? MetricChatColors.timestamp : Colors.black45,
      );
    } else {
      return Icon(
        Icons.done_rounded,
        size: 15,
        color: isDark ? MetricChatColors.timestamp : Colors.black45,
      );
    }
  }
}

/// Isolated widget for real-time presence to prevent whole chat screen invalidation
class _PresenceSubtitle extends StatefulWidget {
  final String peerUid;
  final bool isDark;

  const _PresenceSubtitle({
    required this.peerUid,
    required this.isDark,
  });

  @override
  State<_PresenceSubtitle> createState() => _PresenceSubtitleState();
}

class _PresenceSubtitleState extends State<_PresenceSubtitle> {
  StreamSubscription<DocumentSnapshot>? _sub;
  bool _isOnline = false;
  int? _lastSeen;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _PresenceSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peerUid != widget.peerUid) {
      _sub?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    if (widget.peerUid.isEmpty) return;
    final firestore = FirebaseConfig.firestore;
    if (firestore == null) return;

    _sub = firestore.collection('users').doc(widget.peerUid).snapshots().listen((doc) {
      if (!mounted) return;
      if (!doc.exists) {
        setState(() {
          _isOnline = false;
          _lastSeen = null;
        });
        return;
      }
      final data = doc.data();
      if (data == null) return;

      final isOnline = data['is_online'] as bool? ?? false;
      final lastSeen = (data['last_seen'] as num?)?.toInt() ??
          (data['updated_at'] as num?)?.toInt() ??
          (data['created_at'] as num?)?.toInt();

      setState(() {
        _isOnline = isOnline;
        _lastSeen = lastSeen;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: MetricChatColors.onlineGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'Online',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: MetricChatColors.onlineGreen,
            ),
          ),
        ],
      );
    } else if (_lastSeen != null) {
      return Text(
        _formatLastSeen(_lastSeen!),
        style: TextStyle(
          fontSize: 11,
          color: widget.isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
        ),
      );
    } else {
      return Text(
        'Offline',
        style: TextStyle(
          fontSize: 11,
          color: widget.isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
        ),
      );
    }
  }

  static String _formatLastSeen(int timestampMs) {
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    final isToday = now.year == lastSeen.year && now.month == lastSeen.month && now.day == lastSeen.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == lastSeen.year && yesterday.month == lastSeen.month && yesterday.day == lastSeen.day;

    final timeStr = DateFormat('h:mm a').format(lastSeen);

    if (difference.inSeconds < 60) {
      return 'Last seen just now';
    } else if (isToday) {
      return 'Last seen today at $timeStr';
    } else if (isYesterday) {
      return 'Last seen yesterday at $timeStr';
    } else if (difference.inDays < 7) {
      final dayStr = DateFormat('EEE').format(lastSeen);
      return 'Last seen $dayStr at $timeStr';
    } else {
      final dateStr = DateFormat('MMM d').format(lastSeen);
      return 'Last seen $dateStr';
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
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? MetricColors.background : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? MetricColors.border : AppColors.cardBorderLight,
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text Field in neutral liquid glass pill
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level2 : const Color(0xFFF1F4F9),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark ? MetricGlass.border : Colors.transparent,
                  width: 1.0,
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5,
                minLines: 1,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? MetricColors.textPrimary : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(
                    color: isDark ? MetricColors.textMuted : AppColors.textMutedLight,
                    fontSize: 14,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send Button: subtle turquoise highlight on active, neutral glass when inactive
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hasInputText
                  ? MetricChatColors.sendButton
                  : (isDark ? MetricGlass.level1 : Colors.black12),
              border: Border.all(
                color: _hasInputText
                    ? Colors.transparent
                    : (isDark ? MetricGlass.border : Colors.transparent),
                width: 1.0,
              ),
            ),
            child: IconButton(
              onPressed: _hasInputText ? _submit : null,
              icon: Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: _hasInputText
                    ? Colors.black
                    : (isDark ? MetricColors.textMuted : Colors.black38),
              ),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
