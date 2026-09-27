import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/auth_service.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';
import '../../../core/security/media_crypto.dart';
import '../../../core/backup/google_drive_backup_service.dart';

class ChatState {
  final bool isLoading;
  final List<LocalChatMessage> messages;
  final String myUid;
  final String? peerUid;
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
      channelId: channelId ?? this.channelId,
      isRealtimeConnected: isRealtimeConnected ?? this.isRealtimeConnected,
      errorMessage: errorMessage,
      safetyNumber: safetyNumber ?? this.safetyNumber,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  RealtimeChannel? _realtimeChannel;
  Timer? _pollTimer;
  static const _uuid = Uuid();
  bool _isChatActive = false;

  void setChatActive(bool active) {
    _isChatActive = active;
    if (active) {
      markChatAsRead();
      queryReadStatus();
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
      _pollTimer?.cancel();
      _pollTimer = null;
      if (_realtimeChannel != null) {
        final client = SupabaseConfig.client;
        if (client != null) {
          client.removeChannel(_realtimeChannel!);
        }
        _realtimeChannel = null;
      }
    } catch (_) {}
  }

  /// Initialize local chat state, load SQLite cache, fetch missed messages & start Realtime listener
  Future<void> initChat() async {
    state = state.copyWith(isLoading: true);
    final myUid = await AuthService.getOrCreateDeviceUid();
    final peerUid = await SecureKeyStorage.getPairedUid();
    final safetyNumber = await SignalCryptoService.getSafetyNumber();
    final isVerified = await SecureKeyStorage.isSafetyNumberVerified();

    String? channelId;
    if (peerUid != null) {
      final participants = [myUid, peerUid]..sort();
      channelId = 'ch_${participants.join('_')}';
    }

    // 1. Load local messages from secure SQLite cache
    final localMsgs = await LocalDatabaseService.getMessages();

    state = state.copyWith(
      isLoading: false,
      myUid: myUid,
      peerUid: peerUid,
      channelId: channelId,
      messages: localMsgs,
      safetyNumber: safetyNumber,
      isVerified: isVerified,
    );

    // 2. Fetch any missed messages while offline
    if (peerUid != null) {
      await _fetchMissedMessages(myUid: myUid, peerUid: peerUid);
    }

    // 3. Connect Supabase Realtime listener
    if (peerUid != null) {
      _connectRealtime(myUid: myUid, peerUid: peerUid);

      // 4. Background polling fallback every 3 seconds to guarantee 100% reliable delivery
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (state.peerUid != null) {
          _fetchMissedMessages(myUid: state.myUid, peerUid: state.peerUid!);
        }
      });
    }
  }

  /// Supabase Realtime listener for incoming ciphertext messages & read receipts
  void _connectRealtime({required String myUid, required String peerUid}) {
    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) return;

    try {
      if (_realtimeChannel != null) {
        client.removeChannel(_realtimeChannel!);
        _realtimeChannel = null;
      }

      final participants = [myUid, peerUid]..sort();
      final sharedChannelName = 'chat_shared_${participants.join('_')}';
      final channel = client.channel(sharedChannelName);
      _realtimeChannel = channel;

      // 1. Listen for incoming message inserts
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) async {
          final row = payload.newRecord;
          if (row.isEmpty) return;

          final recipient = row['recipient_uid'] as String?;
          final sender = row['sender_uid'] as String?;

          // Accept only messages addressed to this device from the paired peer
          if (recipient == myUid && sender == peerUid) {
            await _processIncomingMessageRow(row, myUid, peerUid);
          }
        },
      );

      // 2. Listen for Read Receipts: when peer opens chat, turn ticks to BLUE!
      channel.onBroadcast(
        event: 'read_receipt',
        callback: (payload) async {
          final reader = payload['reader_uid'] as String?;
          if (reader == peerUid) {
            await LocalDatabaseService.markAllSentMessagesAsRead(peerUid);
            final updated = await LocalDatabaseService.getMessages();
            state = state.copyWith(messages: updated);
          }
        },
      );

      // 3. Listen for Delivery Receipts: when peer receives message, turn to double GREY ticks!
      channel.onBroadcast(
        event: 'delivery_receipt',
        callback: (payload) async {
          final recipient = payload['recipient_uid'] as String?;
          if (recipient == peerUid) {
            await LocalDatabaseService.markAllSentMessagesAsDelivered(peerUid);
            final updated = await LocalDatabaseService.getMessages();
            state = state.copyWith(messages: updated);
          }
        },
      );

      // 4. Listen for query read status: when peer opens chat and queries if messages are read
      channel.onBroadcast(
        event: 'query_read_status',
        callback: (payload) async {
          final requester = payload['requester_uid'] as String?;
          if (requester == peerUid && _isChatActive) {
            await markChatAsRead();
          }
        },
      );

      channel.subscribe();
      state = state.copyWith(isRealtimeConnected: true);

      // Only notify peer of read status if chat is currently active/open
      if (_isChatActive) {
        markChatAsRead();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProvider] Realtime connect notice: $e');
      }
    }
  }

  /// Parse decrypted text payload into LocalChatMessage (supports text & media messages)
  Future<LocalChatMessage> _parseDecryptedPayload({
    required String msgId,
    required String decryptedText,
    required String senderUid,
    required String receiverUid,
    required int timestamp,
    required bool isMe,
  }) async {
    // Check if decryptedText is an encrypted media envelope JSON
    if (decryptedText.startsWith('{"type":"media"') || decryptedText.contains('"type":"media"')) {
      try {
        final map = jsonDecode(decryptedText) as Map<String, dynamic>;
        if (map['type'] == 'media') {
          final mediaType = map['media_type'] as String? ?? 'document';
          final fileName = map['file_name'] as String? ?? 'file';
          final keyHex = map['key_hex'] as String?;
          final ivHex = map['iv_hex'] as String?;
          final macHex = map['mac_hex'] as String?;
          final dataBase64 = map['data_base64'] as String?;
          final caption = map['caption'] as String?;
          final duration = (map['duration'] as num?)?.toInt();
          final fileSize = (map['file_size'] as num?)?.toInt();

          String? localPath;
          if (dataBase64 != null && keyHex != null && ivHex != null && macHex != null) {
            final ciphertextBytes = base64Decode(dataBase64);
            final decryptedBytes = await MediaCryptoService.decryptMediaBytes(
              ciphertextBytes,
              keyHex: keyHex,
              ivHex: ivHex,
              macHex: macHex,
            );
            localPath = await MediaCryptoService.saveToSandbox(
              decryptedBytes,
              '${msgId}_$fileName',
            );
          }

          return LocalChatMessage(
            id: msgId,
            senderUid: senderUid,
            receiverUid: receiverUid,
            text: caption != null && caption.isNotEmpty ? caption : fileName,
            timestamp: timestamp,
            isMe: isMe,
            status: 'sent',
            mediaType: mediaType,
            localPath: localPath,
            mediaSize: fileSize,
            duration: duration,
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[ChatProvider] Parse media error: $e');
      }
    }

    return LocalChatMessage(
      id: msgId,
      senderUid: senderUid,
      receiverUid: receiverUid,
      text: decryptedText,
      timestamp: timestamp,
      isMe: isMe,
      status: 'sent',
    );
  }

  /// Process an incoming message row: decrypt with Signal ratchet & persist in local SQLite
  Future<void> _processIncomingMessageRow(
    Map<String, dynamic> row,
    String myUid,
    String peerUid,
  ) async {
    final msgId = row['id'] as String?;
    if (msgId == null) return;

    // Check if already processed
    final existing = state.messages.any((m) => m.id == msgId);
    if (existing) return;

    try {
      // Decrypt client-side using Signal Double Ratchet session
      final envelope = EncryptedMessageEnvelope.fromMap(row);
      final decryptedText = await SignalCryptoService.decryptPayload(envelope);

      final localMsg = await _parseDecryptedPayload(
        msgId: msgId,
        decryptedText: decryptedText,
        senderUid: peerUid,
        receiverUid: myUid,
        timestamp: (row['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        isMe: false,
      );

      // Cache decrypted message in local SQLite database
      await LocalDatabaseService.saveMessage(localMsg);
      if (localMsg.mediaType != null) {
        unawaited(GoogleDriveBackupService.instance.queueMediaMessage(localMsg));
      }
      final updated = await LocalDatabaseService.getMessages();
      state = state.copyWith(messages: updated);

      // 1. ALWAYS notify sender that message has arrived on this device (Double GREY tick)
      try {
        _realtimeChannel?.sendBroadcastMessage(
          event: 'delivery_receipt',
          payload: {'recipient_uid': myUid, 'sender_uid': peerUid, 'msg_id': msgId},
        );

        // 2. ONLY notify sender of read receipt (Double BLUE tick) if user has chat ACTIVELY open!
        if (_isChatActive) {
          _realtimeChannel?.sendBroadcastMessage(
            event: 'read_receipt',
            payload: {'reader_uid': myUid, 'peer_uid': peerUid, 'timestamp': DateTime.now().millisecondsSinceEpoch},
          );
        }
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProvider] Decrypt message error: $e');
      }
    }
  }

  /// Notify peer that this device opened the chat (turns peer's sent ticks to BLUE)
  Future<void> markChatAsRead() async {
    final peerUid = state.peerUid;
    if (peerUid == null || peerUid.isEmpty) return;

    try {
      await _realtimeChannel?.sendBroadcastMessage(
        event: 'read_receipt',
        payload: {
          'reader_uid': state.myUid,
          'peer_uid': peerUid,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (_) {}
  }

  /// Query peer if they have opened/read sent messages
  Future<void> queryReadStatus() async {
    final peerUid = state.peerUid;
    if (peerUid == null || peerUid.isEmpty) return;

    try {
      await _realtimeChannel?.sendBroadcastMessage(
        event: 'query_read_status',
        payload: {
          'requester_uid': state.myUid,
          'peer_uid': peerUid,
        },
      );
    } catch (_) {}
  }

  /// Fetch messages from Supabase that arrived while device was offline or if Realtime dropped
  Future<void> _fetchMissedMessages({required String myUid, required String peerUid}) async {
    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) return;

    try {
      final rows = await client
          .from('messages')
          .select()
          .eq('recipient_uid', myUid)
          .eq('sender_uid', peerUid)
          .order('timestamp', ascending: true);

      bool hasNew = false;
      for (final row in rows) {
        final msgId = row['id'] as String?;
        if (msgId == null) continue;

        final alreadyCached = state.messages.any((m) => m.id == msgId);
        if (!alreadyCached) {
          try {
            final envelope = EncryptedMessageEnvelope.fromMap(row);
            final decryptedText = await SignalCryptoService.decryptPayload(envelope);

            final localMsg = await _parseDecryptedPayload(
              msgId: msgId,
              decryptedText: decryptedText,
              senderUid: peerUid,
              receiverUid: myUid,
              timestamp: (row['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
              isMe: false,
            );
            await LocalDatabaseService.saveMessage(localMsg);
            if (localMsg.mediaType != null) {
              unawaited(GoogleDriveBackupService.instance.queueMediaMessage(localMsg));
            }
            hasNew = true;
          } catch (e) {
            if (kDebugMode) debugPrint('[ChatProvider] Parse message error: $e');
          }
        }
      }

      if (hasNew) {
        final updated = await LocalDatabaseService.getMessages();
        state = state.copyWith(messages: updated);

        // Notify sender that messages were delivered to this device
        try {
          _realtimeChannel?.sendBroadcastMessage(
            event: 'delivery_receipt',
            payload: {'recipient_uid': myUid, 'sender_uid': peerUid},
          );
          if (_isChatActive) {
            _realtimeChannel?.sendBroadcastMessage(
              event: 'read_receipt',
              payload: {
                'reader_uid': myUid,
                'peer_uid': peerUid,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              },
            );
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProvider] Fetch missed messages notice: $e');
      }
    }
  }

  /// Send an End-to-End Encrypted Media Message (Photo, Video, Voice Note, Document)
  /// 1. Client-side EXIF stripping & compression (for photos)
  /// 2. AES-256-GCM encryption of media bytes
  /// 3. Save local decrypted copy in private sandbox
  /// 4. Optimistic save in SQLite
  /// 5. Signal session Double Ratchet encryption of media metadata & ciphertext
  /// 6. Insert into Supabase messages table
  Future<void> sendMediaMessage({
    required Uint8List rawBytes,
    required String mediaType, // 'image', 'video', 'voice', 'document'
    required String fileName,
    String? caption,
    int? duration,
  }) async {
    final peerUid = state.peerUid;
    if (peerUid == null || peerUid.isEmpty) {
      state = state.copyWith(errorMessage: 'Cannot send: Device is not paired with a peer.');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final msgId = _uuid.v4();

    // 1. Client-side EXIF stripping & compression for images
    Uint8List processedBytes = rawBytes;
    if (mediaType == 'image') {
      processedBytes = await MediaCryptoService.stripExifAndCompress(rawBytes);
    }

    // 2. Save local decrypted copy in private sandbox
    final localPath = await MediaCryptoService.saveToSandbox(
      processedBytes,
      '${msgId}_$fileName',
    );

    // 3. Immediate optimistic local save
    final displayText = caption != null && caption.isNotEmpty ? caption : fileName;
    final pendingMsg = LocalChatMessage(
      id: msgId,
      senderUid: state.myUid,
      receiverUid: peerUid,
      text: displayText,
      timestamp: now,
      isMe: true,
      status: 'sending',
      mediaType: mediaType,
      localPath: localPath,
      mediaSize: processedBytes.length,
      duration: duration,
    );
    await LocalDatabaseService.saveMessage(pendingMsg);
    unawaited(GoogleDriveBackupService.instance.queueMediaMessage(pendingMsg));
    var updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated, errorMessage: null);

    // 4. Encrypt media bytes with AES-256-GCM
    try {
      final encryptedMedia = await MediaCryptoService.encryptMediaBytes(processedBytes);

      final mediaEnvelope = jsonEncode({
        'type': 'media',
        'media_type': mediaType,
        'file_name': fileName,
        'file_size': processedBytes.length,
        'duration': duration,
        'caption': caption ?? '',
        'key_hex': encryptedMedia.keyHex,
        'iv_hex': encryptedMedia.ivHex,
        'mac_hex': encryptedMedia.macHex,
        'data_base64': base64Encode(encryptedMedia.ciphertext),
      });

      // 5. Encrypt with Signal session Double Ratchet
      final signalEnvelope = await SignalCryptoService.encryptPayload(
        plaintext: mediaEnvelope,
        senderUid: state.myUid,
        receiverUid: peerUid,
      );

      // 6. Write ciphertext to locked-down Supabase messages table
      final client = SupabaseConfig.client;
      if (client != null && SupabaseConfig.isConfigured) {
        await client.from('messages').insert({
          'id': msgId,
          'sender_uid': state.myUid,
          'recipient_uid': peerUid,
          'ciphertext': signalEnvelope.ciphertextHex,
          'iv': signalEnvelope.ivHex,
          'mac': signalEnvelope.macHex,
          'ephemeral_key': signalEnvelope.ephemeralPublicKeyHex,
          'counter': signalEnvelope.counter,
          'timestamp': signalEnvelope.timestamp,
        });

        await LocalDatabaseService.updateMessageStatus(msgId, 'sent');
      } else {
        await LocalDatabaseService.updateMessageStatus(msgId, 'failed');
        state = state.copyWith(errorMessage: 'Network error: Supabase not connected.');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatProvider] Send media error: $e');
      await LocalDatabaseService.updateMessageStatus(msgId, 'failed');
      state = state.copyWith(errorMessage: 'Failed to deliver media: $e');
    }

    updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated);
  }

  /// Send an End-to-End Encrypted Message
  /// 1. Immediate optimistic save in local SQLite (status: sending)
  /// 2. Encrypt with Signal session (ZERO plaintext on wire!)
  /// 3. Insert ciphertext into Supabase messages table
  /// 4. Update status to 'sent' (or 'failed' on network error)
  Future<void> sendMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final peerUid = state.peerUid;
    if (peerUid == null || peerUid.isEmpty) {
      state = state.copyWith(errorMessage: 'Cannot send: Device is not paired with a peer.');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final msgId = _uuid.v4();

    // 1. Immediate optimistic local save with 'sending' status
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
    var updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated, errorMessage: null);

    // 2. Encrypt client-side using Signal session (ZERO plaintext on wire!)
    try {
      final envelope = await SignalCryptoService.encryptPayload(
        plaintext: cleanText,
        senderUid: state.myUid,
        receiverUid: peerUid,
      );

      // 3. Write ciphertext to locked-down Supabase messages table
      final client = SupabaseConfig.client;
      if (client != null && SupabaseConfig.isConfigured) {
        await client.from('messages').insert({
          'id': msgId,
          'sender_uid': state.myUid,
          'recipient_uid': peerUid,
          'ciphertext': envelope.ciphertextHex,
          'iv': envelope.ivHex,
          'mac': envelope.macHex,
          'ephemeral_key': envelope.ephemeralPublicKeyHex,
          'counter': envelope.counter,
          'timestamp': envelope.timestamp,
        });

        // 4. Update status to 'sent'
        await LocalDatabaseService.updateMessageStatus(msgId, 'sent');
      } else {
        await LocalDatabaseService.updateMessageStatus(msgId, 'failed');
        state = state.copyWith(errorMessage: 'Network error: Supabase not connected.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProvider] Send error: $e');
      }
      await LocalDatabaseService.updateMessageStatus(msgId, 'failed');
      state = state.copyWith(errorMessage: 'Failed to deliver message: $e');
    }

    updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated);
  }

  /// Retry sending a failed message
  Future<void> retryMessage(String msgId) async {
    final msg = state.messages.firstWhere((m) => m.id == msgId);
    if (!msg.isMe || msg.status != 'failed') return;

    final peerUid = state.peerUid;
    if (peerUid == null) return;

    // Mark as sending
    await LocalDatabaseService.updateMessageStatus(msgId, 'sending');
    var updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated);

    try {
      final envelope = await SignalCryptoService.encryptPayload(
        plaintext: msg.text,
        senderUid: state.myUid,
        receiverUid: peerUid,
      );

      final client = SupabaseConfig.client;
      if (client != null && SupabaseConfig.isConfigured) {
        await client.from('messages').upsert({
          'id': msgId,
          'sender_uid': state.myUid,
          'recipient_uid': peerUid,
          'ciphertext': envelope.ciphertextHex,
          'iv': envelope.ivHex,
          'mac': envelope.macHex,
          'ephemeral_key': envelope.ephemeralPublicKeyHex,
          'counter': envelope.counter,
          'timestamp': envelope.timestamp,
        });

        await LocalDatabaseService.updateMessageStatus(msgId, 'sent');
      } else {
        await LocalDatabaseService.updateMessageStatus(msgId, 'failed');
      }
    } catch (e) {
      await LocalDatabaseService.updateMessageStatus(msgId, 'failed');
    }

    updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated);
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

  /// Delete message from local storage
  Future<void> deleteMessage(String id) async {
    await LocalDatabaseService.deleteMessage(id);
    final updated = await LocalDatabaseService.getMessages();
    state = state.copyWith(messages: updated);
  }

  /// Purge all local decrypted messages
  Future<void> clearAllMessages() async {
    await LocalDatabaseService.clearAllMessages();
    state = state.copyWith(messages: []);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
