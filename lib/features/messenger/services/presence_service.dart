import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../../core/config/firebase_config.dart';
import '../../../core/security/secure_key_storage.dart';

/// Lightweight presence management service for Metric Messenger.
/// Updates `is_online` and `last_seen` on the user's Firestore document.
/// Only marks user online while actively inside the chat application (not in decoy converter).
class PresenceService {
  static final PresenceService instance = PresenceService._();
  PresenceService._();

  bool _isInChatApp = false;
  bool _isResumed = true;

  bool get isOnline => _isInChatApp && _isResumed;

  /// Called when the user opens the decrypted messenger (ChatListHomeScreen)
  Future<void> enterChatApp() async {
    _isInChatApp = true;
    await _updatePresence(true);
  }

  /// Called when the user exits the messenger back to calculator decoy or logs out
  Future<void> exitChatApp() async {
    _isInChatApp = false;
    await _updatePresence(false);
  }

  /// Called by the app lifecycle observer in main.dart
  Future<void> onAppLifecycleChanged(AppLifecycleState state) async {
    _isResumed = state == AppLifecycleState.resumed;
    if (_isInChatApp) {
      await _updatePresence(_isResumed);
    }
  }

  /// Update presence fields on user document
  Future<void> _updatePresence(bool online) async {
    final myUid = await SecureKeyStorage.getMyDeviceId();
    if (myUid == null || myUid.isEmpty) return;

    final firestore = FirebaseConfig.firestore;
    if (firestore == null) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await firestore.collection('users').doc(myUid).set({
        'is_online': online,
        'last_seen': now,
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[PresenceService] Update presence error: $e');
    }
  }
}
