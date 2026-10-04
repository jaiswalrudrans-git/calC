import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../features/messenger/models/chat_contact.dart';
import '../database/local_cache.dart';
import '../security/secure_key_storage.dart';
import '../security/signal_crypto.dart';

/// Top-level background message handler for Firebase Messaging.
/// Executes in a background isolate when the app is backgrounded or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(dynamic remoteMessage) async {
  try {
    await Firebase.initializeApp();
    final data = remoteMessage.data as Map<String, dynamic>?;
    if (data == null) return;

    final conversationId = data['conversationId'] as String?;
    final messageId = data['messageId'] as String?;

    if (conversationId != null && conversationId.isNotEmpty) {
      await DecoyNotificationService.showBackgroundDecoyNotification(
        conversationId: conversationId,
        messageId: messageId,
      );
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[DecoyNotification] Background message error: $e');
  }
}

/// Production-grade Decoy Notification Service for Metric / calC.
/// Displays completely generic utility notifications that mimic a calculator app.
///
/// Features:
/// - Replaces existing notification per conversation using deterministic IDs.
/// - Suppresses repeated chimes/vibrations during rapid message bursts (onlyAlertOnce + debounce).
/// - Completely suppresses notifications when the user is actively viewing that chat.
/// - Clears notification on opening conversation.
/// - Zero leak of sender, message, media, or encryption data.
class DecoyNotificationService {
  static final DecoyNotificationService instance = DecoyNotificationService._internal();
  DecoyNotificationService._internal();

  static const String channelId = 'calC_messages';
  static const String channelName = 'calC';
  static const String channelDescription = 'calC notifications';

  static const String decoyTitle = 'calC';
  static const String decoyBody = 'Your answer is ready';

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Currently open chat conversation ID (null if in calculator, settings, or chat list)
  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  /// Pending navigation target from tapped notification (consumed after vault unlock)
  String? _pendingConversationId;
  String? consumePendingConversationId() {
    final id = _pendingConversationId;
    _pendingConversationId = null;
    return id;
  }

  /// In-memory message deduplication set
  final Set<String> _processedMessageIds = <String>{};

  /// Timestamp tracking for alert sound debounce (cooldown in milliseconds)
  final Map<String, int> _lastAlertTimestamps = <String, int>{};
  static const int _alertCooldownMs = 5000; // 5 seconds burst window

  /// Realtime Firestore subscriptions across user contacts
  final List<StreamSubscription> _channelSubscriptions = [];

  /// Initialize local notification channels and plugins
  Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create high-priority decoy Android notification channel
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }

    _isInitialized = true;
    if (kDebugMode) debugPrint('[DecoyNotification] Initialized successfully');
  }

  /// Request notification permission on Android 13+ and iOS
  Future<bool> requestPermission() async {
    try {
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        return granted ?? false;
      }

      final iosPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DecoyNotification] Permission request error: $e');
    }
    return false;
  }

  /// Deterministic 31-bit positive integer hash for a conversation ID.
  /// The same conversation ALWAYS maps to the exact same notification ID across app launches.
  static int notificationIdForConversation(String conversationId) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < conversationId.length; i++) {
      hash ^= conversationId.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final id = hash & 0x7FFFFFFF;
    return id == 0 ? 1 : id;
  }

  /// Set which conversation is currently active on screen.
  /// Suppresses notifications for this conversation while open.
  void setActiveConversation(String? convId) {
    _activeConversationId = convId;
    if (convId != null) {
      // Clear tray notification for the opened conversation
      unawaited(cancelConversationNotification(convId));
    }
  }

  /// Display or replace a decoy notification for an incoming message.
  Future<void> showDecoyNotification({
    required String conversationId,
    String? messageId,
  }) async {
    // 1. Check user preferences
    final enabled = await SecureKeyStorage.getNotificationsEnabled();
    if (!enabled) return;

    // 2. Suppress if user is currently looking at this conversation
    if (_activeConversationId == conversationId) {
      return;
    }

    // 3. Message ID idempotency
    if (messageId != null) {
      if (_processedMessageIds.contains(messageId)) {
        return;
      }
      _processedMessageIds.add(messageId);
      if (_processedMessageIds.length > 500) {
        _processedMessageIds.remove(_processedMessageIds.first);
      }
    }

    final notifId = notificationIdForConversation(conversationId);

    // 4. Determine if sound/vibration should trigger (cooldown / debounce)
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAlert = _lastAlertTimestamps[conversationId] ?? 0;
    final isBurst = (now - lastAlert) < _alertCooldownMs;

    if (!isBurst) {
      _lastAlertTimestamps[conversationId] = now;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      onlyAlertOnce: true, // Prevents repetitive chiming/vibration on replacements!
      playSound: !isBurst,
      enableVibration: !isBurst,
      showWhen: true,
      autoCancel: true,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: !isBurst,
      threadIdentifier: conversationId,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notifId,
      title: decoyTitle,
      body: decoyBody,
      notificationDetails: details,
      payload: jsonEncode({'conversationId': conversationId}),
    );
  }

  /// Static helper for showing a decoy notification from a background isolate.
  static Future<void> showBackgroundDecoyNotification({
    required String conversationId,
    String? messageId,
  }) async {
    final enabled = await SecureKeyStorage.getNotificationsEnabled();
    if (!enabled) return;

    final plugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await plugin.initialize(settings: const InitializationSettings(android: androidSettings, iOS: iosSettings));

    final notifId = notificationIdForConversation(conversationId);

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      onlyAlertOnce: true,
      playSound: true,
      enableVibration: true,
      showWhen: true,
      autoCancel: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: channelId,
    );

    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await plugin.show(
      id: notifId,
      title: decoyTitle,
      body: decoyBody,
      notificationDetails: details,
      payload: jsonEncode({'conversationId': conversationId}),
    );
  }

  /// Cancel notification for a specific conversation when opened.
  Future<void> cancelConversationNotification(String conversationId) async {
    try {
      final notifId = notificationIdForConversation(conversationId);
      await _localNotifications.cancel(id: notifId);
    } catch (e) {
      if (kDebugMode) debugPrint('[DecoyNotification] Cancel notification error: $e');
    }
  }

  /// Cancel all active notifications.
  Future<void> cancelAll() async {
    try {
      await _localNotifications.cancelAll();
    } catch (e) {
      if (kDebugMode) debugPrint('[DecoyNotification] Cancel all error: $e');
    }
  }

  /// Handle notification tap in foreground or cold-start.
  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final convId = data['conversationId'] as String?;
        if (convId != null) {
          _pendingConversationId = convId;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[DecoyNotification] Payload parse error: $e');
      }
    }
  }

  /// Start persistent realtime listener across all contacts in Firestore.
  /// Runs seamlessly while the app is active in foreground or background.
  void startRealtimeListener({
    required String myUid,
    required List<ChatContact> contacts,
  }) {
    stopRealtimeListener();

    if (myUid.isEmpty || contacts.isEmpty) return;

    final firestore = FirebaseFirestore.instance;

    for (final contact in contacts.take(5)) {
      final participants = [myUid, contact.uid]..sort();
      final channelId = 'ch_${participants.join('_')}';

      try {
        final sub = firestore
            .collection('chats')
            .doc(channelId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(10)
            .snapshots()
            .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data();
              if (data == null) continue;

              final msgId = (data['id'] as String?) ?? change.doc.id;
              final senderUid = data['sender_uid'] as String? ?? '';
              final recipientUid = data['recipient_uid'] as String? ?? '';
              final status = data['status'] as String? ?? 'sent';

              // Only process incoming messages meant for me
              if (recipientUid != myUid || senderUid == myUid) continue;
              if (status == 'read') continue;

              // Immediately acknowledge delivery to the sender when this device receives the message
              if (status == 'sent') {
                unawaited(change.doc.reference.update({'status': 'delivered'}));
              }

              // If user is actively inside this conversation, ChatNotifier handles live decryption and UI
              if (_activeConversationId == channelId) {
                continue;
              }

              // Check if already processed
              if (_processedMessageIds.contains(msgId)) continue;
              _processedMessageIds.add(msgId);
              if (_processedMessageIds.length > 500) {
                _processedMessageIds.remove(_processedMessageIds.first);
              }

              // Decrypt and save locally if not already present
              try {
                final existing = await LocalDatabaseService.getMessageById(msgId);
                if (existing == null) {
                  final timestamp =
                      (data['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
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
                  } catch (_) {
                    decryptedText = '[Encrypted Message]';
                  }

                  final localMsg = LocalChatMessage(
                    id: msgId,
                    senderUid: senderUid,
                    receiverUid: recipientUid,
                    text: decryptedText,
                    timestamp: timestamp,
                    isMe: false,
                    status: 'delivered',
                  );
                  await LocalDatabaseService.saveMessage(localMsg);
                }
              } catch (_) {}

              // Display or replace decoy notification
              await showDecoyNotification(
                conversationId: channelId,
                messageId: msgId,
              );
            } else if (change.type == DocumentChangeType.removed) {
              final data = change.doc.data();
              final msgId = (data?['id'] as String?) ?? change.doc.id;
              unawaited(LocalDatabaseService.deleteMessage(msgId));
            }
          }
        }, onError: (err) {
          if (kDebugMode) debugPrint('[DecoyNotification] Realtime listener error: $err');
        });

        _channelSubscriptions.add(sub);
      } catch (e) {
        if (kDebugMode) debugPrint('[DecoyNotification] Failed to listen to channel $channelId: $e');
      }
    }
  }

  /// Stop all active realtime listeners (e.g. on logout)
  void stopRealtimeListener() {
    for (final sub in _channelSubscriptions) {
      sub.cancel();
    }
    _channelSubscriptions.clear();
  }
}
