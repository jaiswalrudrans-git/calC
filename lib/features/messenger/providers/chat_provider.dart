import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/auth_service.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';

class ChatState {
  final bool isLoading;
  final List<LocalChatMessage> messages;
  final String myUid;
  final String? peerUid;
  final String? channelId;
  final int disappearingSeconds; // 0 = off, 86400 = 1 day, 604800 = 7 days
  final LocalChatMessage? replyingTo;

  const ChatState({
    this.isLoading = false,
    this.messages = const [],
    this.myUid = '',
    this.peerUid,
    this.channelId,
    this.disappearingSeconds = 0,
    this.replyingTo,
  });

  ChatState copyWith({
    bool? isLoading,
    List<LocalChatMessage>? messages,
    String? myUid,
    String? peerUid,
    String? channelId,
    int? disappearingSeconds,
    LocalChatMessage? replyingTo,
  }) {
    return ChatState(
      isLoading: isLoading ?? this.isLoading,
      messages: messages ?? this.messages,
      myUid: myUid ?? this.myUid,
      peerUid: peerUid ?? this.peerUid,
      channelId: channelId ?? this.channelId,
      disappearingSeconds: disappearingSeconds ?? this.disappearingSeconds,
      replyingTo: replyingTo,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  StreamSubscription? _firestoreSubscription;
  Timer? _cleanupTimer;

  @override
  ChatState build() {
    ref.onDispose(() {
      _firestoreSubscription?.cancel();
      _cleanupTimer?.cancel();
    });

    initChat();
    return const ChatState();
  }

  Future<void> initChat() async {
    state = state.copyWith(isLoading: true);
    final myUid = await AuthService.getOrCreateDeviceUid();
    final peerUid = await SecureKeyStorage.getPairedUid();
    final timerSeconds = await SecureKeyStorage.getDisappearingTimerSeconds();

    String? channelId;
    if (peerUid != null) {
      final participants = [myUid, peerUid]..sort();
      channelId = 'ch_${participants.join('_')}';
    }

    // Load local messages first
    final localMsgs = await LocalDatabaseService.getMessages();

    state = state.copyWith(
      isLoading: false,
      myUid: myUid,
      peerUid: peerUid,
      channelId: channelId,
      disappearingSeconds: timerSeconds,
      messages: localMsgs,
    );

    // Start realtime listener if Firestore & Channel are active
    if (Firebase.apps.isNotEmpty && channelId != null) {
      _listenToFirestoreChannel(channelId, myUid);
    }

    // Periodic cleanup of expired ephemeral messages
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) => _purgeExpired());
  }

  void _listenToFirestoreChannel(String channelId, String myUid) {
    _firestoreSubscription?.cancel();
    try {
      final ref = FirebaseFirestore.instance
          .collection('channels')
          .doc(channelId)
          .collection('messages')
          .orderBy('timestamp', descending: false);

      _firestoreSubscription = ref.snapshots().listen((snapshot) async {
        for (final docChange in snapshot.docChanges) {
          if (docChange.type == DocumentChangeType.added) {
            final data = docChange.doc.data();
            if (data == null) continue;

            final sender = data['senderUid'] as String? ?? '';
            // Only process messages from peer (local messages are already saved locally)
            if (sender != myUid) {
              final envelope = EncryptedMessageEnvelope.fromFirestore(data);
              // Check expiration
              if (envelope.expiresAt != null &&
                  DateTime.now().millisecondsSinceEpoch > envelope.expiresAt!) {
                continue; // Expired
              }

              // Decrypt client-side using Signal Double Ratchet
              final decryptedText = await SignalCryptoService.decryptPayload(envelope);

              final localMsg = LocalChatMessage(
                id: docChange.doc.id,
                senderUid: sender,
                receiverUid: myUid,
                text: decryptedText,
                timestamp: envelope.timestamp,
                expiresAt: envelope.expiresAt,
                isMe: false,
                mediaType: data['mediaType'] as String?,
              );

              await LocalDatabaseService.saveMessage(localMsg);
            }
          }
        }

        // Refresh UI list
        final updatedMsgs = await LocalDatabaseService.getMessages();
        state = state.copyWith(messages: updatedMsgs);
      });
    } catch (_) {
      // Offline fallback
    }
  }

  /// Send an End-to-End Encrypted Message
  Future<void> sendMessage(String text, {String? mediaType}) async {
    if (text.trim().isEmpty && mediaType == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final msgId = const Uuid().v4();
    final peerUid = state.peerUid ?? 'peer_device';

    final expiresAt = state.disappearingSeconds > 0
        ? now + (state.disappearingSeconds * 1000)
        : null;

    // 1. Client-Side E2E Encryption (Signal Double Ratchet)
    final envelope = await SignalCryptoService.encryptPayload(
      plaintext: text,
      senderUid: state.myUid,
      receiverUid: peerUid,
      disappearingDurationSeconds: state.disappearingSeconds,
    );

    // 2. Save locally decrypted copy in secure SQLite cache
    final localMsg = LocalChatMessage(
      id: msgId,
      senderUid: state.myUid,
      receiverUid: peerUid,
      text: text,
      timestamp: now,
      expiresAt: expiresAt,
      isMe: true,
      mediaType: mediaType,
    );
    await LocalDatabaseService.saveMessage(localMsg);

    // 3. Write CIPHERTEXT ONLY to Firestore channel
    if (Firebase.apps.isNotEmpty && state.channelId != null) {
      try {
        final firestoreData = envelope.toFirestoreMap();
        if (mediaType != null) firestoreData['mediaType'] = mediaType;
        firestoreData['participants'] = [state.myUid, peerUid];

        await FirebaseFirestore.instance
            .collection('channels')
            .doc(state.channelId)
            .collection('messages')
            .doc(msgId)
            .set(firestoreData);
      } catch (_) {
        // Transparent offline handling
      }
    }

    final updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated, replyingTo: null);
  }

  Future<void> setReaction(String messageId, String? reaction) async {
    await LocalDatabaseService.updateReaction(messageId, reaction);
    final updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated);
  }

  Future<void> setDisappearingTimer(int seconds) async {
    await SecureKeyStorage.setDisappearingTimerSeconds(seconds);
    state = state.copyWith(disappearingSeconds: seconds);
  }

  void setReplyingTo(LocalChatMessage? msg) {
    state = state.copyWith(replyingTo: msg);
  }

  Future<void> deleteMessage(String id) async {
    await LocalDatabaseService.deleteMessage(id);
    if (Firebase.apps.isNotEmpty && state.channelId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('channels')
            .doc(state.channelId)
            .collection('messages')
            .doc(id)
            .delete();
      } catch (_) {}
    }
    final updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated);
  }

  Future<void> _purgeExpired() async {
    final updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
