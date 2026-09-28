import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/firebase_config.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/auth_service.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';

class ChatState {
  final bool isLoading;
  final List<LocalChatMessage> messages;
  final String myUid;
  final String? peerUid;
  final String? peerName;
  final String? channelId;
  final bool isRealtimeConnected;
  final String? errorMessage;
  final String? safetyNumber;
  final bool isVerified;

  const ChatState({
    this.isLoading = false,
    this.messages = const [],
    this.myUid = '',
    this.peerUid,
    this.peerName,
    this.channelId,
    this.isRealtimeConnected = false,
    this.errorMessage,
    this.safetyNumber,
    this.isVerified = false,
  });

  ChatState copyWith({
    bool? isLoading,
    List<LocalChatMessage>? messages,
    String? myUid,
    String? peerUid,
    String? peerName,
    String? channelId,
    bool? isRealtimeConnected,
    String? errorMessage,
    String? safetyNumber,
    bool? isVerified,
  }) {
    return ChatState(
      isLoading: isLoading ?? this.isLoading,
      messages: messages ?? this.messages,
      myUid: myUid ?? this.myUid,
      peerUid: peerUid ?? this.peerUid,
      peerName: peerName ?? this.peerName,
      channelId: channelId ?? this.channelId,
      isRealtimeConnected: isRealtimeConnected ?? this.isRealtimeConnected,
      errorMessage: errorMessage,
      safetyNumber: safetyNumber ?? this.safetyNumber,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  StreamSubscription<QuerySnapshot>? _firestoreSub;
  static const _uuid = Uuid();
  bool _isChatActive = false;

  void setChatActive(bool active) {
    _isChatActive = active;
    if (active) {
      markChatAsRead();
    }
  }

  bool get isChatActive => _isChatActive;

  @override
  ChatState build() {
    ref.onDispose(() {
      _cleanup();
    });

    Future.microtask(() => initChat());
    return const ChatState(isLoading: true);
  }

  void _cleanup() {
    try {
      _firestoreSub?.cancel();
      _firestoreSub = null;
    } catch (_) {}
  }

  /// Switch or initialize active chat conversation with a specific contact
  Future<void> setActivePeer(String peerUid, {String? contactName}) async {
    _cleanup();
    await initChat(explicitPeerUid: peerUid, contactName: contactName);
  }

  /// Initialize local chat state, load SQLite cache, and start Firestore realtime listener
  Future<void> initChat({String? explicitPeerUid, String? contactName}) async {
    state = state.copyWith(isLoading: true);

    await AuthService.ensureFirebaseAuth();

    final myUid = await AuthService.getOrCreateDeviceUid();
    final peerUid = explicitPeerUid ?? await SecureKeyStorage.getPairedUid();
    final safetyNumber = await SignalCryptoService.getSafetyNumber();
    final isVerified = await SecureKeyStorage.isSafetyNumberVerified();

    String? channelId;
    if (peerUid != null && peerUid.isNotEmpty) {
      final participants = [myUid, peerUid]..sort();
      channelId = 'ch_${participants.join('_')}';
    }

    // 1. Load local messages from secure SQLite cache
    final localMsgs = peerUid != null
        ? await LocalDatabaseService.getMessagesForPeer(peerUid, myUid: myUid)
        : await LocalDatabaseService.getMessages();

    state = state.copyWith(
      isLoading: false,
      myUid: myUid,
      peerUid: peerUid,
      peerName: contactName ?? state.peerName ?? 'Contact',
      channelId: channelId,
      messages: localMsgs,
      safetyNumber: safetyNumber,
      isVerified: isVerified,
    );

    // 2. Connect Firestore Realtime listener for zero-latency instant messaging
    if (peerUid != null && channelId != null) {
      _connectFirestoreListener(myUid: myUid, peerUid: peerUid, channelId: channelId);
    }
  }

  /// Listen to Cloud Firestore realtime snapshot stream
  void _connectFirestoreListener({
    required String myUid,
    required String peerUid,
    required String channelId,
  }) {
    _firestoreSub?.cancel();

    final firestore = FirebaseConfig.firestore;
    if (firestore == null) {
      state = state.copyWith(isRealtimeConnected: false);
      return;
    }

    try {
      final messagesCollection = firestore
          .collection('chats')
          .doc(channelId)
          .collection('messages')
          .orderBy('timestamp', descending: false);

      _firestoreSub = messagesCollection.snapshots().listen(
        (snapshot) async {
          state = state.copyWith(isRealtimeConnected: true);
          bool hasChanges = false;

          for (final change in snapshot.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;

            final msgId = (data['id'] as String?) ?? change.doc.id;
            final senderUid = data['sender_uid'] as String? ?? '';
            final recipientUid = data['recipient_uid'] as String? ?? '';
            final status = data['status'] as String? ?? 'sent';
            final timestamp = (data['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

            if (change.type == DocumentChangeType.added) {
              final existingIndex = state.messages.indexWhere((m) => m.id == msgId);
              final isEncryptedPlaceholder = existingIndex >= 0 && state.messages[existingIndex].text.contains('[Encrypted');

              if (existingIndex < 0 || isEncryptedPlaceholder) {
                final isMe = senderUid == myUid;
                String decryptedText = '';

                try {
                  final envelope = EncryptedMessageEnvelope(
                    senderUid: senderUid,
                    receiverUid: recipientUid,
                    ephemeralPublicKeyHex: data['ephemeral_key'] as String? ?? '',
                    counter: (data['counter'] as num?)?.toInt() ?? 0,
                    ivHex: data['iv'] as String? ?? '',
                    ciphertextHex: data['ciphertext'] as String? ?? '',
                    macHex: data['mac'] as String? ?? '',
                    timestamp: timestamp,
                  );
                  decryptedText = await SignalCryptoService.decryptPayload(envelope);
                } catch (e) {
                  decryptedText = '[Encrypted Message]';
                }

                final localMsg = LocalChatMessage(
                  id: msgId,
                  senderUid: senderUid,
                  receiverUid: recipientUid,
                  text: decryptedText,
                  timestamp: timestamp,
                  isMe: isMe,
                  status: status,
                );

                await LocalDatabaseService.saveMessage(localMsg);
                hasChanges = true;

                // Update receipt in Firestore if received by me
                if (!isMe && recipientUid == myUid) {
                  final newStatus = _isChatActive ? 'read' : 'delivered';
                  try {
                    await change.doc.reference.update({'status': newStatus});
                  } catch (_) {}
                }
              }
            } else if (change.type == DocumentChangeType.modified) {
              await LocalDatabaseService.updateMessageStatus(msgId, status);
              hasChanges = true;
            }
          }

          if (hasChanges) {
            final updated = await LocalDatabaseService.getMessagesForPeer(peerUid, myUid: myUid);
            state = state.copyWith(messages: updated);
          }
        },
        onError: (error) {
          if (kDebugMode) debugPrint('[ChatProvider] Firestore snapshot error: $error');
          state = state.copyWith(isRealtimeConnected: false);
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatProvider] Firestore connect error: $e');
    }
  }

  /// Send an End-to-End Encrypted Text Message via Firebase Spark (Cloud Firestore)
  Future<void> sendMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final peerUid = state.peerUid;
    if (peerUid == null || peerUid.isEmpty) {
      state = state.copyWith(errorMessage: 'Cannot send: No active contact selected.');
      return;
    }

    final channelId = state.channelId;
    if (channelId == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final msgId = _uuid.v4();

    // 1. Immediate optimistic save in SQLite (status: sending)
    final pendingMsg = LocalChatMessage(
      id: msgId,
      senderUid: state.myUid,
      receiverUid: peerUid,
      text: cleanText,
      timestamp: now,
      isMe: true,
      status: 'sending',
    );
    await LocalDatabaseService.saveMessage(pendingMsg);
    var localList = await LocalDatabaseService.getMessagesForPeer(peerUid);
    state = state.copyWith(messages: localList, errorMessage: null);

    // 2. Encrypt with Signal Protocol session (ZERO plaintext over the wire)
    try {
      final signalEnvelope = await SignalCryptoService.encryptPayload(
        plaintext: cleanText,
        senderUid: state.myUid,
        receiverUid: peerUid,
      );

      final rowData = {
        'id': msgId,
        'sender_uid': state.myUid,
        'recipient_uid': peerUid,
        'ciphertext': signalEnvelope.ciphertextHex,
        'iv': signalEnvelope.ivHex,
        'mac': signalEnvelope.macHex,
        'ephemeral_key': signalEnvelope.ephemeralPublicKeyHex,
        'counter': signalEnvelope.counter,
        'timestamp': signalEnvelope.timestamp,
        'status': 'sent',
      };

      // 3. Write ciphertext to Cloud Firestore
      final firestore = FirebaseConfig.firestore;
      if (firestore != null) {
        await firestore
            .collection('chats')
            .doc(channelId)
            .collection('messages')
            .doc(msgId)
            .set(rowData);

        await LocalDatabaseService.updateMessageStatus(msgId, 'sent');
      } else {
        await LocalDatabaseService.updateMessageStatus(msgId, 'failed');
        state = state.copyWith(errorMessage: 'Network error: Firebase not connected.');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatProvider] Send message error: $e');
      await LocalDatabaseService.updateMessageStatus(msgId, 'failed');
      state = state.copyWith(errorMessage: 'Failed to send message: $e');
    }

    localList = await LocalDatabaseService.getMessagesForPeer(peerUid);
    state = state.copyWith(messages: localList);
  }

  /// Mark all received messages as read
  Future<void> markChatAsRead() async {
    final peerUid = state.peerUid;
    final channelId = state.channelId;
    if (peerUid == null || channelId == null) return;

    final firestore = FirebaseConfig.firestore;
    if (firestore == null) return;

    try {
      final unreadDocs = await firestore
          .collection('chats')
          .doc(channelId)
          .collection('messages')
          .where('recipient_uid', isEqualTo: state.myUid)
          .where('status', isNotEqualTo: 'read')
          .get();

      for (final doc in unreadDocs.docs) {
        await doc.reference.update({'status': 'read'});
      }
    } catch (_) {}
  }

  /// Retry sending a failed message
  Future<void> retryMessage(String messageId) async {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final failedMsg = state.messages[index];
    await deleteMessage(messageId);
    await sendMessage(failedMsg.text);
  }

  /// Delete message from local storage and Cloud Firestore
  Future<void> deleteMessage(String id) async {
    await LocalDatabaseService.deleteMessage(id);
    final peerUid = state.peerUid;
    if (peerUid != null) {
      final updated = await LocalDatabaseService.getMessagesForPeer(peerUid);
      state = state.copyWith(messages: updated);
    }

    final channelId = state.channelId;
    final firestore = FirebaseConfig.firestore;
    if (channelId != null && firestore != null) {
      try {
        await firestore
            .collection('chats')
            .doc(channelId)
            .collection('messages')
            .doc(id)
            .delete();
      } catch (_) {}
    }
  }

  /// Purge all local decrypted messages for this peer
  Future<void> clearAllMessages() async {
    final peerUid = state.peerUid;
    if (peerUid != null) {
      final db = await LocalDatabaseService.database;
      await db.delete(
        'messages',
        where: 'senderUid = ? OR receiverUid = ?',
        whereArgs: [peerUid, peerUid],
      );
      state = state.copyWith(messages: []);
    }
  }

  /// Toggle safety number verification status
  Future<void> toggleSafetyVerification() async {
    final next = !state.isVerified;
    await SecureKeyStorage.setSafetyNumberVerified(next);
    state = state.copyWith(isVerified: next);
  }

  /// Refresh safety number
  Future<void> refreshSafetyNumber() async {
    final sn = await SignalCryptoService.getSafetyNumber();
    final verified = await SecureKeyStorage.isSafetyNumberVerified();
    state = state.copyWith(safetyNumber: sn, isVerified: verified);
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
