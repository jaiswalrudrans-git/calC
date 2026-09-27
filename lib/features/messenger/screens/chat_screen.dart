import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/privacy_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../pairing/screens/pairing_screen.dart';
import '../providers/chat_provider.dart';

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
    PrivacyGuard.setScreenProtection(true);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    PrivacyGuard.setScreenProtection(false);
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final state = ref.read(chatProvider);
    if (state.peerUid == null || state.peerUid!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot send: Device is not paired with a peer. Pair first.'),
          backgroundColor: AppColors.alertRed,
        ),
      );
      return;
    }

    _textController.clear();
    HapticFeedback.lightImpact();
    ref.read(chatProvider.notifier).sendMessage(text);

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

  void _showVerificationSheet(BuildContext context, ChatState state, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final liveState = ref.watch(chatProvider);
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      liveState.isVerified ? Icons.verified_user_rounded : Icons.shield_rounded,
                      color: liveState.isVerified ? AppColors.secureGreen : AppColors.primary,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Connection Security & ID Verification',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'End-to-End Encrypted via Signal Protocol',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                ),
                const SizedBox(height: 18),

                // 12-Digit Safety Number Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF132A22) : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.secureGreen.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '12-DIGIT SAFETY NUMBER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: AppColors.secureGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        liveState.safetyNumber ?? 'Generating...',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.5,
                          fontFamily: 'monospace',
                          color: AppColors.secureGreen,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Speak out or compare this number with your peer. If identical, you have mathematical proof that you are connected directly with zero eavesdropping.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Device ID Details
                _buildIdRow(
                  label: 'MY DEVICE ID',
                  id: liveState.myUid,
                  isDark: isDark,
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: liveState.myUid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('My Device ID copied to clipboard'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildIdRow(
                  label: 'CONNECTED PEER ID',
                  id: liveState.peerUid ?? 'Not Paired',
                  isDark: isDark,
                  isPeer: true,
                  onCopy: liveState.peerUid != null
                      ? () {
                          Clipboard.setData(ClipboardData(text: liveState.peerUid!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Peer Device ID copied to clipboard'), duration: Duration(seconds: 1)),
                          );
                        }
                      : null,
                ),
                const SizedBox(height: 20),

                // Verification Toggle Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      ref.read(chatProvider.notifier).toggleSafetyVerification();
                    },
                    icon: Icon(
                      liveState.isVerified ? Icons.check_circle_rounded : Icons.verified_outlined,
                      size: 20,
                    ),
                    label: Text(
                      liveState.isVerified ? 'Marked as Verified Partner ✓' : 'Mark Partner as Verified',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: liveState.isVerified ? AppColors.secureGreen : AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildIdRow({
    required String label,
    required String id,
    required bool isDark,
    bool isPeer = false,
    VoidCallback? onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2235) : const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isPeer ? AppColors.secureGreen : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  id,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 16),
              tooltip: 'Copy',
              onPressed: onCopy,
            ),
        ],
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
        title: GestureDetector(
          onTap: () => _showVerificationSheet(context, state, isDark),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    state.isVerified ? Icons.verified_user_rounded : Icons.lock_rounded,
                    size: 16,
                    color: state.isVerified ? AppColors.secureGreen : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text('Metric E2E', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(width: 4),
                  if (state.isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.secureGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'VERIFIED',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.secureGreen),
                      ),
                    ),
                ],
              ),
              Text(
                state.peerUid != null
                    ? 'Peer: ${state.peerUid!.substring(0, state.peerUid!.length > 8 ? 8 : state.peerUid!.length)}... • Tap to verify'
                    : 'Not Paired • Tap to verify',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              state.isVerified ? Icons.verified_user_rounded : Icons.shield_outlined,
              color: state.isVerified ? AppColors.secureGreen : null,
            ),
            tooltip: 'Security & Verification',
            onPressed: () => _showVerificationSheet(context, state, isDark),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Warning Banner if Not Paired
            if (state.peerUid == null || state.peerUid!.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.warningAmber.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warningAmber),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Device not paired with a peer. Tap to pair.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warningAmber),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const PairingScreen()),
                        );
                      },
                      child: const Text('Pair Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),

            // Error Banner if error occurred
            if (state.errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.alertRed.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.alertRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(fontSize: 12, color: AppColors.alertRed, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.alertRed),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => ref.read(chatProvider.notifier).clearError(),
                    ),
                  ],
                ),
              ),

            // Message List
            Expanded(
              child: state.isLoading && state.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : state.messages.isEmpty
                      ? _buildEmptyState(isDark)
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

            // Input Bar
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_rounded, size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'End-to-End Encrypted',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Messages are encrypted with the Signal Protocol on your device before reaching Supabase. Zero plaintext exists on any server.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(LocalChatMessage msg, bool isDark) {
    final timeStr = DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: msg.isMe
                  ? AppColors.primary
                  : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(msg.isMe ? 18 : 4),
                bottomRight: Radius.circular(msg.isMe ? 4 : 18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  msg.text,
                  style: TextStyle(
                    fontSize: 15,
                    color: msg.isMe
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
                        color: msg.isMe
                            ? Colors.white.withValues(alpha: 0.7)
                            : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                      ),
                    ),
                    if (msg.isMe) ...[
                      const SizedBox(width: 4),
                      if (msg.status == 'sending')
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
                        )
                      else if (msg.status == 'failed')
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            ref.read(chatProvider.notifier).retryMessage(msg.id);
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 13, color: AppColors.alertRed),
                              SizedBox(width: 2),
                              Text('Retry', style: TextStyle(fontSize: 10, color: AppColors.alertRed)),
                            ],
                          ),
                        )
                      else
                        const Icon(Icons.done_rounded, size: 12, color: Colors.white70),
                    ],
                  ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'Encrypted Message...',
                hintStyle: TextStyle(
                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E2235) : const Color(0xFFF1F4F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sendMessage,
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}
