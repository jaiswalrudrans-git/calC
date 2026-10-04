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

  /// Switch or initialize active chat conversation with a specific contact instantly
  Future<void> setActivePeer(String peerUid, {String? contactName}) async {
    _cleanup();

    final myUid = state.myUid.isNotEmpty ? state.myUid : await AuthService.getOrCreateDeviceUid();
    final participants = [myUid, peerUid]..sort();
    final channelId = 'ch_${participants.join('_')}';

    // 1. Instant local message retrieval from memory/SQLite
    final localMsgs = await LocalDatabaseService.getMessagesForPeer(peerUid, myUid: myUid);

    state = state.copyWith(
      isLoading: false,
      myUid: myUid,
      peerUid: peerUid,
      peerName: contactName ?? state.peerName ?? 'Contact',
      channelId: channelId,
      messages: localMsgs,
    );

    // 2. Load safety number asynchronously in background
    unawaited(() async {
      final safetyNumber = await SignalCryptoService.getSafetyNumber();
      final isVerified = await SecureKeyStorage.isSafetyNumberVerified();
      state = state.copyWith(safetyNumber: safetyNumber, isVerified: isVerified);
    }());

    // 3. Connect Firestore Realtime listener for zero-latency instant messaging
    _connectFirestoreListener(myUid: myUid, peerUid: peerUid, channelId: channelId);
  }

  /// Initialize local chat state, load SQLite cache, and start Firestore realtime listener
  Future<void> initChat({String? explicitPeerUid, String? contactName}) async {
    final myUid = state.myUid.isNotEmpty ? state.myUid : await AuthService.getOrCreateDeviceUid();
    final peerUid = explicitPeerUid ?? await SecureKeyStorage.getPairedUid();

    String? channelId;
    if (peerUid != null && peerUid.isNotEmpty) {
      final participants = [myUid, peerUid]..sort();
      channelId = 'ch_${participants.join('_')}';
    }

    // 1. Show cached local messages immediately without showing a blank spinner
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
    );

    // 2. Background verification
    unawaited(() async {
      await AuthService.ensureFirebaseAuth();
      final safetyNumber = await SignalCryptoService.getSafetyNumber();
      final isVerified = await SecureKeyStorage.isSafetyNumberVerified();
      state = state.copyWith(safetyNumber: safetyNumber, isVerified: isVerified);
    }());

    // 3. Connect Firestore Realtime listener
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

              if (existingIndex >= 0 && !isEncryptedPlaceholder) {
                if (state.messages[existingIndex].status != status) {
                  _updateMessageStatusInMemory(msgId, status);
                  unawaited(LocalDatabaseService.updateMessageStatus(msgId, status));
                }
              } else {
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

                final updatedList = List<LocalChatMessage>.from(state.messages);
                if (existingIndex >= 0) {
                  updatedList[existingIndex] = localMsg;
                } else {
                  updatedList.add(localMsg);
                }
                state = state.copyWith(messages: updatedList);
                unawaited(LocalDatabaseService.saveMessage(localMsg));
              }

              // Update receipt in Firestore if received by me
              if (senderUid != myUid && recipientUid == myUid) {
                if (_isChatActive) {
                  if (status != 'read') {
                    unawaited(change.doc.reference.update({'status': 'read'}));
                  }
                } else {
                  if (status == 'sent') {
                    unawaited(change.doc.reference.update({'status': 'delivered'}));
                  }
                }
              }
            } else if (change.type == DocumentChangeType.modified) {
              _updateMessageStatusInMemory(msgId, status);
              unawaited(LocalDatabaseService.updateMessageStatus(msgId, status));
            }
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

  void _updateMessageStatusInMemory(String msgId, String status) {
    final idx = state.messages.indexWhere((m) => m.id == msgId);
    if (idx != -1) {
      final updatedList = List<LocalChatMessage>.from(state.messages);
      updatedList[idx] = updatedList[idx].copyWith(status: status);
      state = state.copyWith(messages: updatedList);
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

    // 1. Immediate in-memory optimistic bubble (Frame 0 - 0ms latency)
    final pendingMsg = LocalChatMessage(
      id: msgId,
      senderUid: state.myUid,
      receiverUid: peerUid,
      text: cleanText,
      timestamp: now,
      isMe: true,
      status: 'sending',
    );
    state = state.copyWith(
      messages: [...state.messages, pendingMsg],
      errorMessage: null,
    );

    // Save to SQLite asynchronously
    unawaited(LocalDatabaseService.saveMessage(pendingMsg));

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

        unawaited(LocalDatabaseService.updateMessageStatus(msgId, 'sent'));
        _updateMessageStatusInMemory(msgId, 'sent');
      } else {
        unawaited(LocalDatabaseService.updateMessageStatus(msgId, 'failed'));
        _updateMessageStatusInMemory(msgId, 'failed');
        state = state.copyWith(errorMessage: 'Network error: Firebase not connected.');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatProvider] Send message error: $e');
      unawaited(LocalDatabaseService.updateMessageStatus(msgId, 'failed'));
      _updateMessageStatusInMemory(msgId, 'failed');
      state = state.copyWith(errorMessage: 'Failed to send message: $e');
    }
  }

  /// Mark all received messages as read
  Future<void> markChatAsRead() async {
    final peerUid = state.peerUid;
    final channelId = state.channelId;
    if (peerUid == null || channelId == null) return;

    // 1. Immediately update local database and in-memory state
    await LocalDatabaseService.markAllReceivedMessagesAsRead(peerUid);
    final hasUnread = state.messages.any((m) => !m.isMe && m.status != 'read');
    if (hasUnread) {
      final updated = state.messages.map((m) {
        if (!m.isMe && m.status != 'read') {
          return m.copyWith(status: 'read');
        }
        return m;
      }).toList();
      state = state.copyWith(messages: updated);
    }

    final firestore = FirebaseConfig.firestore;
    if (firestore == null) return;

    try {
      final messagesSnap = await firestore
          .collection('chats')
          .doc(channelId)
          .collection('messages')
          .get();

      final batch = firestore.batch();
      bool hasBatchDocs = false;
      for (final doc in messagesSnap.docs) {
        final data = doc.data();
        final rUid = data['recipient_uid'] as String?;
        final status = data['status'] as String?;
        if (rUid == state.myUid && status != 'read') {
          batch.update(doc.reference, {'status': 'read'});
          hasBatchDocs = true;
        }
      }
      if (hasBatchDocs) {
        await batch.commit();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatProvider] markChatAsRead error: $e');
    }
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
