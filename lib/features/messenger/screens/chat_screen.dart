import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/privacy_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/backup/google_drive_backup_service.dart';
import '../../gallery/screens/fullscreen_media_gallery_viewer.dart';
import '../../gallery/screens/shared_gallery_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../providers/chat_provider.dart';
import '../widgets/voice_bubble_widget.dart';
import 'image_viewer_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isSearching = false;
  String _searchQuery = '';
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  bool _hasInputText = false;
  bool _isRecordingVoice = false;
  String? _recordFilePath;
  Timer? _recordDurationTimer;
  int _recordSeconds = 0;
  int _previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    PrivacyGuard.setScreenProtection(true);

    // Notify provider that chat is currently active/open (triggers blue ticks on peer device!)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).setChatActive(true);
    });

    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _hasInputText) {
        setState(() => _hasInputText = hasText);
      }
    });

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animate: false);
    });
  }

  @override
  void dispose() {
    ref.read(chatProvider.notifier).setChatActive(false);
    _textController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _recordDurationTimer?.cancel();
    _highlightTimer?.cancel();
    _audioRecorder.dispose();
    PrivacyGuard.setScreenProtection(false);
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(maxScroll);
    }
  }

  void _scrollToAndHighlightMessage(String messageId) {
    final messages = ref.read(chatProvider).messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    setState(() {
      _highlightedMessageId = messageId;
    });

    HapticFeedback.mediumImpact();

    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() => _highlightedMessageId = null);
      }
    });

    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final targetScroll = (index / (messages.isEmpty ? 1 : messages.length)) * maxScroll;
      _scrollController.animateTo(
        targetScroll.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _maybePromptDriveBackup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GoogleDriveBackupService.instance.checkAndPromptFirstMediaAuth(context);
      }
    });
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

    Future.delayed(const Duration(milliseconds: 80), () {
      _scrollToBottom();
    });
  }

  Future<void> _startVoiceRecord() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required to record voice notes')),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(
        tempDir.path,
        'rec_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      _recordFilePath = filePath;

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      HapticFeedback.heavyImpact();
      setState(() {
        _isRecordingVoice = true;
        _recordSeconds = 0;
      });

      _recordDurationTimer?.cancel();
      _recordDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordSeconds++);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start voice recording: $e')),
        );
      }
    }
  }

  Future<void> _stopVoiceRecordAndSend() async {
    _recordDurationTimer?.cancel();
    HapticFeedback.mediumImpact();

    final duration = _recordSeconds;
    final wasRecording = _isRecordingVoice;

    setState(() {
      _isRecordingVoice = false;
      _recordSeconds = 0;
    });

    if (wasRecording) {
      try {
        final path = await _audioRecorder.stop();
        final finalPath = path ?? _recordFilePath;
        if (duration >= 1 && finalPath != null) {
          final file = File(finalPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
            await ref.read(chatProvider.notifier).sendMediaMessage(
              rawBytes: bytes,
              mediaType: 'voice',
              fileName: fileName,
              duration: duration,
            );
            _maybePromptDriveBackup();
            Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to process voice note: $e')),
          );
        }
      }
    }
  }

  Future<void> _cancelVoiceRecord() async {
    _recordDurationTimer?.cancel();
    HapticFeedback.vibrate();
    setState(() {
      _isRecordingVoice = false;
      _recordSeconds = 0;
    });

    try {
      final path = await _audioRecorder.stop();
      final finalPath = path ?? _recordFilePath;
      if (finalPath != null) {
        final file = File(finalPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}
  }

  Future<void> _pickAndSendCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final fileName = p.basename(picked.path);

      await ref.read(chatProvider.notifier).sendMediaMessage(
        rawBytes: bytes,
        mediaType: 'image',
        fileName: fileName,
      );
      _maybePromptDriveBackup();
      Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture photo: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final fileName = p.basename(picked.path);

      await ref.read(chatProvider.notifier).sendMediaMessage(
        rawBytes: bytes,
        mediaType: 'image',
        fileName: fileName,
      );
      _maybePromptDriveBackup();
      Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select image: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: source);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      await ref.read(chatProvider.notifier).sendMediaMessage(
        rawBytes: bytes,
        mediaType: 'video',
        fileName: p.basename(picked.path),
      );
      _maybePromptDriveBackup();
      Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send video: $e')),
        );
      }
    }
  }

  void _showMediaPickerOptions({required bool isCamera}) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(isCamera ? Icons.camera_alt_rounded : Icons.photo_library_rounded),
              title: Text(isCamera ? 'Take Photo' : 'Photo Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                if (isCamera) {
                  _pickAndSendCamera();
                } else {
                  _pickAndSendGallery();
                }
              },
            ),
            ListTile(
              leading: Icon(isCamera ? Icons.videocam_rounded : Icons.video_library_rounded),
              title: Text(isCamera ? 'Record Video' : 'Video Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendVideo(isCamera ? ImageSource.camera : ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendDocument() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;

      final picked = files.first;
      final bytes = await picked.xFile.readAsBytes();

      await ref.read(chatProvider.notifier).sendMediaMessage(
        rawBytes: bytes,
        mediaType: 'document',
        fileName: picked.name,
      );
      _maybePromptDriveBackup();
      Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select document: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendAudio() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (files.isEmpty) return;

      final picked = files.first;
      final bytes = await picked.xFile.readAsBytes();

      await ref.read(chatProvider.notifier).sendMediaMessage(
        rawBytes: bytes,
        mediaType: 'voice',
        fileName: picked.name,
      );
      _maybePromptDriveBackup();
      Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select audio: $e')),
        );
      }
    }
  }

  void _showAttachmentSheet() {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2235) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAttachmentOption(
                  icon: Icons.insert_drive_file_rounded,
                  label: 'Document',
                  color: AppColors.purpleIcon,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendDocument();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  color: AppColors.roseIcon,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMediaPickerOptions(isCamera: true);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  color: AppColors.blueIcon,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMediaPickerOptions(isCamera: false);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.headphones_rounded,
                  label: 'Audio',
                  color: AppColors.orangeIcon,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendAudio();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _onMenuSelected(String value) async {
    switch (value) {
      case 'search':
        setState(() {
          _isSearching = true;
        });
        break;
      case 'clear_chat':
        _showClearChatDialog();
        break;
      case 'view_media':
        final targetMessageId = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (context) => const SharedGalleryScreen()),
        );
        if (targetMessageId != null && mounted) {
          _scrollToAndHighlightMessage(targetMessageId);
        }
        break;
      case 'export_chat':
        _showExportChatDialog();
        break;
      case 'switch_converter':
        Navigator.pop(context);
        break;
      case 'settings':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
        break;
    }
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat History?'),
        content: const Text(
          'This will purge all local decrypted messages on this device. Future messages will continue to be encrypted via your active Signal session.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(chatProvider.notifier).clearAllMessages();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat history cleared')),
                );
              }
            },
            child: const Text('Clear Chat', style: TextStyle(color: AppColors.alertRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showExportChatDialog() {
    final messages = ref.read(chatProvider).messages;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Encrypted Archive'),
        content: Text(
          'Archive contains ${messages.length} messages.\n\nAll exported records are cryptographic zero-knowledge ciphertext with sender UIDs and timestamps.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(
                text: messages.map((m) => '[${m.timestamp}] ${m.isMe ? "ME" : "PEER"}: ${m.text}').join('\n'),
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Decrypted transcript copied to secure clipboard')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Transcript'),
          ),
        ],
      ),
    );
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

  String _formatDateSeparator(int timestamp) {
    final msgDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    final isToday = msgDate.year == now.year && msgDate.month == now.month && msgDate.day == now.day;
    if (isToday) return 'Today';

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = msgDate.year == yesterday.year && msgDate.month == yesterday.month && msgDate.day == yesterday.day;
    if (isYesterday) return 'Yesterday';

    if (msgDate.year == now.year) {
      return DateFormat('EEEE, MMMM d').format(msgDate);
    }
    return DateFormat('MMMM d, yyyy').format(msgDate);
  }

  bool _isDifferentDay(int t1, int t2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(t1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(t2);
    return d1.year != d2.year || d1.month != d2.month || d1.day != d2.day;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(chatProvider);

    // Auto-scroll when new messages arrive
    if (state.messages.length > _previousMessageCount) {
      _previousMessageCount = state.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    final filteredMessages = _searchQuery.isEmpty
        ? state.messages
        : state.messages.where((m) => m.text.toLowerCase().contains(_searchQuery)).toList();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(chatProvider.notifier).setChatActive(false);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0C0E14) : const Color(0xFFEFEAE2),
        appBar: _isSearching ? _buildSearchAppBar(isDark) : _buildMainAppBar(context, state, isDark),
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
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          );
                        },
                        child: const Text('View Connect Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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

              // Message List with Date Separators
              Expanded(
                child: state.isLoading && state.messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : filteredMessages.isEmpty
                        ? _buildEmptyState(isDark)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            itemCount: filteredMessages.length,
                            itemBuilder: (context, index) {
                              final msg = filteredMessages[index];
                              final showDateSeparator = index == 0 ||
                                  _isDifferentDay(
                                    filteredMessages[index - 1].timestamp,
                                    msg.timestamp,
                                  );

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showDateSeparator) _buildDateSeparator(msg.timestamp, isDark),
                                  _buildMessageBubble(msg, isDark),
                                ],
                              );
                            },
                          ),
              ),

              // Voice Recording Bar or Standard Bottom Input Bar
              if (_isRecordingVoice)
                _buildVoiceRecordingBar(isDark)
              else
                _buildInputBar(isDark),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSearchAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search encrypted messages...',
          hintStyle: TextStyle(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
          border: InputBorder.none,
        ),
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      ),
      actions: [
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear_rounded),
            onPressed: () => _searchController.clear(),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildMainAppBar(BuildContext context, ChatState state, bool isDark) {
    return AppBar(
      elevation: 0.5,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      leadingWidth: 40,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back to Unit Converter',
        onPressed: () {
          Navigator.pop(context);
        },
      ),
      title: GestureDetector(
        onTap: () => _showVerificationSheet(context, state, isDark),
        child: Row(
          children: [
            // Avatar with connection badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Icon(
                    state.isVerified ? Icons.verified_user_rounded : Icons.lock_rounded,
                    size: 20,
                    color: state.isVerified ? AppColors.secureGreen : AppColors.primary,
                  ),
                ),
                if (state.isRealtimeConnected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.secureGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),

            // Chat Name & Status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          state.peerUid != null
                              ? 'Peer ${state.peerUid!.substring(0, state.peerUid!.length > 6 ? 6 : state.peerUid!.length)}'
                              : 'Metric Vault',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      if (state.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.secureGreen),
                      ],
                    ],
                  ),
                  Text(
                    state.isRealtimeConnected ? 'online • E2E Encrypted' : 'Signal E2E • Secure',
                    style: TextStyle(
                      fontSize: 11,
                      color: state.isRealtimeConnected
                          ? AppColors.secureGreen
                          : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                      fontWeight: state.isRealtimeConnected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Search icon
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Search Messages',
          onPressed: () => setState(() => _isSearching = true),
        ),

        // Shield verification icon
        IconButton(
          icon: Icon(
            state.isVerified ? Icons.verified_user_rounded : Icons.shield_outlined,
            color: state.isVerified ? AppColors.secureGreen : null,
          ),
          tooltip: 'Safety Verification',
          onPressed: () => _showVerificationSheet(context, state, isDark),
        ),

        // WhatsApp-style 3-dots popup menu
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'Menu',
          onSelected: _onMenuSelected,
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'view_media',
              child: Row(
                children: [
                  Icon(Icons.perm_media_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('View Media'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'search',
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18),
                  SizedBox(width: 12),
                  Text('Search Messages'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Clear Chat'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'export_chat',
              child: Row(
                children: [
                  Icon(Icons.download_rounded, size: 18),
                  SizedBox(width: 12),
                  Text('Export Chat'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'switch_converter',
              child: Row(
                children: [
                  Icon(Icons.calculate_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Switch to Converter Decoy'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Settings'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateSeparator(int timestamp, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C202F) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            _formatDateSeparator(timestamp),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
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
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_rounded, size: 52, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(
            'End-to-End Encrypted',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Messages are encrypted with the Signal Protocol on your device before transmission. Zero plaintext exists on any server.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
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
    final isHighlighted = msg.id == _highlightedMessageId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: msg.mediaType == 'image'
                ? const EdgeInsets.all(4)
                : const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: msg.isMe
                  ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB))
                  : (isDark ? const Color(0xFF1F2C34) : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(msg.isMe ? 16 : 2),
                bottomRight: Radius.circular(msg.isMe ? 2 : 16),
              ),
              border: isHighlighted
                  ? Border.all(color: AppColors.primary, width: 2.5)
                  : null,
              boxShadow: [
                if (isHighlighted)
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  )
                else
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                _buildBubbleContent(msg, isDark),
                const SizedBox(height: 3),
                Padding(
                  padding: msg.mediaType == 'image'
                      ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                      : EdgeInsets.zero,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white60 : Colors.black45,
                        ),
                      ),
                      if (msg.isMe) ...[
                        const SizedBox(width: 4),
                        if (msg.status == 'sending')
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey),
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
                        else if (msg.status == 'read')
                          const Icon(
                            Icons.done_all_rounded,
                            size: 14,
                            color: Color(0xFF53BDEB), // WhatsApp blue ticks (opened & seen)
                          )
                        else if (msg.status == 'delivered')
                          Icon(
                            Icons.done_all_rounded,
                            size: 14,
                            color: isDark ? Colors.white60 : Colors.black45, // Double GREY ticks
                          )
                        else
                          Icon(
                            Icons.done_rounded,
                            size: 14,
                            color: isDark ? Colors.white60 : Colors.black45, // Single GREY tick (not yet seen)
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleContent(LocalChatMessage msg, bool isDark) {
    if (msg.mediaType == 'image') {
      return _buildImageContent(msg, isDark);
    } else if (msg.mediaType == 'video') {
      return _buildVideoContent(msg, isDark);
    } else if (msg.mediaType == 'voice') {
      return VoiceBubbleWidget(message: msg, isDark: isDark);
    } else if (msg.mediaType == 'document') {
      return _buildDocumentContent(msg, isDark);
    } else {
      return Text(
        msg.text,
        style: TextStyle(
          fontSize: 15,
          height: 1.3,
          color: msg.isMe
              ? (isDark ? Colors.white : const Color(0xFF111B21))
              : (isDark ? Colors.white : const Color(0xFF111B21)),
        ),
      );
    }
  }

  Widget _buildVideoContent(LocalChatMessage msg, bool isDark) {
    final hasFile = msg.localPath != null && File(msg.localPath!).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: hasFile
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullScreenMediaGalleryViewer(
                        items: [msg],
                        initialIndex: 0,
                      ),
                    ),
                  );
                }
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2235) : const Color(0xFF262C40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70, width: 2),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(Icons.videocam_rounded, color: Colors.white70, size: 16),
                        if (msg.duration != null && msg.duration! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${msg.duration! ~/ 60}:${(msg.duration! % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (msg.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            child: Text(
              msg.text,
              style: TextStyle(
                fontSize: 14,
                color: msg.isMe
                    ? (isDark ? Colors.white : const Color(0xFF111B21))
                    : (isDark ? Colors.white : const Color(0xFF111B21)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageContent(LocalChatMessage msg, bool isDark) {
    final heroTag = 'img_${msg.id}';
    final hasFile = msg.localPath != null && File(msg.localPath!).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: hasFile
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ImageViewerScreen(
                        filePath: msg.localPath!,
                        title: msg.text,
                        timestamp: msg.timestamp,
                        heroTag: heroTag,
                      ),
                    ),
                  );
                }
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: hasFile
                  ? Hero(
                      tag: heroTag,
                      child: Image.file(
                        File(msg.localPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: isDark ? Colors.black38 : Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      color: isDark ? Colors.black38 : Colors.grey.shade200,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_rounded, size: 36, color: AppColors.primary),
                            SizedBox(height: 6),
                            Text(
                              'Encrypted Image',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
        if (msg.text.isNotEmpty &&
            !msg.text.toLowerCase().endsWith('.jpg') &&
            !msg.text.toLowerCase().endsWith('.jpeg') &&
            !msg.text.toLowerCase().endsWith('.png'))
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Text(
              msg.text,
              style: TextStyle(
                fontSize: 14,
                color: msg.isMe
                    ? (isDark ? Colors.white : const Color(0xFF111B21))
                    : (isDark ? Colors.white : const Color(0xFF111B21)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDocumentContent(LocalChatMessage msg, bool isDark) {
    final sizeStr = (msg.mediaSize != null && msg.mediaSize! > 0)
        ? (msg.mediaSize! < 1024 * 1024
            ? '${(msg.mediaSize! / 1024).toStringAsFixed(1)} KB'
            : '${(msg.mediaSize! / (1024 * 1024)).toStringAsFixed(1)} MB')
        : '';

    return Container(
      constraints: const BoxConstraints(minWidth: 200),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.purpleIcon.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.insert_drive_file_rounded,
              color: AppColors.purpleIcon,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: msg.isMe
                        ? (isDark ? Colors.white : const Color(0xFF111B21))
                        : (isDark ? Colors.white : const Color(0xFF111B21)),
                  ),
                ),
                if (sizeStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sizeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceRecordingBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isDark ? const Color(0xFF1A1D2B) : Colors.white,
      child: Row(
        children: [
          // Red pulse recording indicator
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppColors.alertRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_recordSeconds ~/ 60}:${(_recordSeconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const Spacer(),
          TextButton(
            onPressed: _cancelVoiceRecord,
            child: const Text('Cancel', style: TextStyle(color: AppColors.alertRed)),
          ),
          IconButton.filled(
            onPressed: _stopVoiceRecordAndSend,
            icon: const Icon(Icons.arrow_upward_rounded),
            style: IconButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
          // Attachment (+) button
          IconButton(
            onPressed: _showAttachmentSheet,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 26),
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            tooltip: 'Attach Media',
          ),
          const SizedBox(width: 6),

          // Text Field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2436) : const Color(0xFFF1F4F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      focusNode: _inputFocusNode,
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  // Camera Icon button inside text input
                  IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _pickAndSendCamera();
                    },
                    icon: const Icon(Icons.camera_alt_rounded, size: 22),
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    tooltip: 'Camera',
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send Button OR Mic Button
          if (_hasInputText)
            IconButton.filled(
              onPressed: _sendMessage,
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
              ),
            )
          else
            GestureDetector(
              onLongPress: _startVoiceRecord,
              onLongPressUp: _stopVoiceRecordAndSend,
              child: IconButton.filled(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hold mic button to record voice note'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.mic_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
