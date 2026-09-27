import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/supabase_config.dart';
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

  /// Supabase Realtime listener for incoming ciphertext messages
  void _connectRealtime({required String myUid, required String peerUid}) {
    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) return;

    try {
      if (_realtimeChannel != null) {
        client.removeChannel(_realtimeChannel!);
        _realtimeChannel = null;
      }

      final channel = client.channel('chat_realtime_$myUid');
      _realtimeChannel = channel;

      // Listen to insert events without client-side column filters (Supabase RLS handles authorization)
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
      ).subscribe();

      state = state.copyWith(isRealtimeConnected: true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProvider] Realtime connect notice: $e');
      }
    }
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

      final localMsg = LocalChatMessage(
        id: msgId,
        senderUid: peerUid,
        receiverUid: myUid,
        text: decryptedText,
        timestamp: (row['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        isMe: false,
        status: 'sent',
      );

      // Cache decrypted message in local SQLite database
      await LocalDatabaseService.saveMessage(localMsg);
      final updated = await LocalDatabaseService.getMessages();
      state = state.copyWith(messages: updated);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProvider] Decrypt message error: $e');
      }
    }
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

            final localMsg = LocalChatMessage(
              id: msgId,
              senderUid: peerUid,
              receiverUid: myUid,
              text: decryptedText,
              timestamp: (row['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
              isMe: false,
              status: 'sent',
            );
            await LocalDatabaseService.saveMessage(localMsg);
            hasNew = true;
          } catch (e) {
            if (kDebugMode) debugPrint('[ChatProvider] Parse message error: $e');
          }
        }
      }

      if (hasNew) {
        final updated = await LocalDatabaseService.getMessages();
        state = state.copyWith(messages: updated);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProvider] Fetch missed messages notice: $e');
      }
    }
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
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
