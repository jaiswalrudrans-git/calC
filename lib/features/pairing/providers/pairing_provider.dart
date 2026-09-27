import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/database/local_cache.dart';
import '../../../core/security/auth_service.dart';
import '../../../core/security/secure_key_storage.dart';
import '../../../core/security/signal_crypto.dart';

class PairingState {
  final bool isLoading;
  final String myPairingCode;
  final String myDeviceUid;
  final PublicKeyBundle? myBundle;
  final bool isPaired;
  final String? peerUid;
  final bool isListeningForPeer;
  final String? errorMessage;
  final String? successMessage;
  final String? safetyNumber;

  const PairingState({
    this.isLoading = false,
    this.myPairingCode = '',
    this.myDeviceUid = '',
    this.myBundle,
    this.isPaired = false,
    this.peerUid,
    this.isListeningForPeer = false,
    this.errorMessage,
    this.successMessage,
    this.safetyNumber,
  });

  PairingState copyWith({
    bool? isLoading,
    String? myPairingCode,
    String? myDeviceUid,
    PublicKeyBundle? myBundle,
    bool? isPaired,
    String? peerUid,
    bool? isListeningForPeer,
    String? errorMessage,
    String? successMessage,
    String? safetyNumber,
  }) {
    return PairingState(
      isLoading: isLoading ?? this.isLoading,
      myPairingCode: myPairingCode ?? this.myPairingCode,
      myDeviceUid: myDeviceUid ?? this.myDeviceUid,
      myBundle: myBundle ?? this.myBundle,
      isPaired: isPaired ?? this.isPaired,
      peerUid: peerUid ?? this.peerUid,
      isListeningForPeer: isListeningForPeer ?? this.isListeningForPeer,
      errorMessage: errorMessage,
      successMessage: successMessage,
      safetyNumber: safetyNumber ?? this.safetyNumber,
    );
  }
}

class PairingNotifier extends Notifier<PairingState> {
  RealtimeChannel? _realtimeChannel;

  @override
  PairingState build() {
    ref.onDispose(() {
      _cleanupRealtime();
    });

    Future.microtask(() => init());
    return const PairingState(isLoading: true);
  }

  void _cleanupRealtime() {
    try {
      if (_realtimeChannel != null) {
        final client = SupabaseConfig.client;
        if (client != null) {
          client.removeChannel(_realtimeChannel!);
        }
        _realtimeChannel = null;
      }
    } catch (_) {}
  }

  /// Initialize local keys, silent auth, and publish beacon if not paired
  Future<void> init() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // 1. Generate or retrieve Signal Protocol identity key pair + prekeys locally
      await SignalCryptoService.ensurePrekeyBundle();
      final myBundle = await SignalCryptoService.getLocalPublicKeyBundle();

      // 2. Silent Supabase Anonymous Auth
      final uid = await AuthService.getOrCreateDeviceUid();
      final paired = await SecureKeyStorage.isPaired();
      final peerUid = await SecureKeyStorage.getPairedUid();
      final safetyNumber = await SignalCryptoService.getSafetyNumber();

      final code = SignalCryptoService.generateRandomPairingCode();

      state = state.copyWith(
        isLoading: false,
        myPairingCode: code,
        myDeviceUid: uid,
        myBundle: myBundle,
        isPaired: paired,
        peerUid: peerUid,
        safetyNumber: safetyNumber,
      );

      // 3. If not already paired, publish row to Supabase pairing_exchange & listen via Realtime
      if (!paired) {
        await publishBeacon(code);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Device A: Publish pairing row to `pairing_exchange` and subscribe to Supabase Realtime
  Future<void> publishBeacon(String code) async {
    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) {
      if (kDebugMode) {
        debugPrint('[Pairing] Supabase client not yet configured.');
      }
      return;
    }

    try {
      final uid = state.myDeviceUid.isNotEmpty
          ? state.myDeviceUid
          : await AuthService.getOrCreateDeviceUid();
      final bundle = state.myBundle ?? await SignalCryptoService.getLocalPublicKeyBundle();

      // Insert own row under `code`
      await client.from('pairing_exchange').upsert({
        'code': code,
        'uid': uid,
        'public_key_bundle': bundle.toJson(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (kDebugMode) {
        debugPrint('[Pairing] Beacon published under code: $code for UID: $uid');
      }

      state = state.copyWith(isListeningForPeer: true);

      // Subscribe to Supabase Realtime for Device B's response under `${code}_b`
      _cleanupRealtime();
      final responseCode = '${code}_b';
      final channel = client.channel('pairing_$code');
      _realtimeChannel = channel;

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'pairing_exchange',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'code',
          value: responseCode,
        ),
        callback: (payload) async {
          final record = payload.newRecord;
          if (record.isNotEmpty) {
            final peerUid = record['uid'] as String?;
            final bundleRaw = record['public_key_bundle'];

            if (peerUid != null && bundleRaw != null) {
              final Map<String, dynamic> bundleMap = bundleRaw is String
                  ? jsonDecode(bundleRaw)
                  : Map<String, dynamic>.from(bundleRaw as Map);
              final peerBundle = PublicKeyBundle.fromJson(bundleMap);

              // Store exchanged public keys + peer UID in flutter_secure_storage & init ratchet
              await SignalCryptoService.saveRemotePeerBundle(
                peerUid: peerUid,
                bundle: peerBundle,
              );

              // Print/log (debug only) that both are present in secure storage
              await SecureKeyStorage.printDebugPairingStatus();

              // Delete own row from pairing_exchange
              try {
                await client.from('pairing_exchange').delete().eq('code', code);
              } catch (e) {
                if (kDebugMode) debugPrint('[Pairing] Delete beacon error: $e');
              }

              _cleanupRealtime();
              final sn = await SignalCryptoService.getSafetyNumber();

              state = state.copyWith(
                isPaired: true,
                peerUid: peerUid,
                isListeningForPeer: false,
                safetyNumber: sn,
                successMessage: 'Paired successfully! Public keys exchanged.',
              );
            }
          }
        },
      ).subscribe();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Pairing] Failed to publish beacon: $e');
      }
    }
  }

  /// Device B: Enter Device A's code, fetch A's public key bundle, insert own bundle under `${code}_b`
  Future<bool> pairWithCode(String peerCodeInput) async {
    final cleanCode = peerCodeInput.replaceAll('-', '').replaceAll(' ', '').trim();
    if (cleanCode.isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter a valid pairing code');
      return false;
    }

    final client = SupabaseConfig.client;
    if (client == null || !SupabaseConfig.isConfigured) {
      state = state.copyWith(
        errorMessage: 'Supabase is not configured yet. Set credentials in lib/core/config/supabase_config.dart',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // 1. Fetch Device A's row from pairing_exchange
      final row = await client
          .from('pairing_exchange')
          .select()
          .eq('code', cleanCode)
          .maybeSingle();

      if (row == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'No active pairing request found for code "$cleanCode". Check the code and try again.',
        );
        return false;
      }

      final peerUid = row['uid'] as String?;
      final peerBundleRaw = row['public_key_bundle'];

      if (peerUid == null || peerBundleRaw == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Invalid pairing row received from server.',
        );
        return false;
      }

      final Map<String, dynamic> peerBundleMap = peerBundleRaw is String
          ? jsonDecode(peerBundleRaw)
          : Map<String, dynamic>.from(peerBundleRaw as Map);
      final peerBundle = PublicKeyBundle.fromJson(peerBundleMap);

      // 2. Ensure local keys and UID exist for Device B
      final myUid = state.myDeviceUid.isNotEmpty
          ? state.myDeviceUid
          : await AuthService.getOrCreateDeviceUid();
      final myBundle = state.myBundle ?? await SignalCryptoService.getLocalPublicKeyBundle();

      // 3. Store Device A's public key bundle + UID in flutter_secure_storage & init ratchet
      await SignalCryptoService.saveRemotePeerBundle(
        peerUid: peerUid,
        bundle: peerBundle,
      );

      // 4. Insert Device B's own row under `${cleanCode}_b`
      final responseCode = '${cleanCode}_b';
      await client.from('pairing_exchange').upsert({
        'code': responseCode,
        'uid': myUid,
        'public_key_bundle': myBundle.toJson(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 5. Confirm locally: Print/log debug pairing verification
      await SecureKeyStorage.printDebugPairingStatus();

      // 6. Delete Device B's response row after short delay to allow Device A's Realtime receipt
      Future.delayed(const Duration(seconds: 4), () async {
        try {
          await client.from('pairing_exchange').delete().eq('code', responseCode);
        } catch (_) {}
      });

      final sn = await SignalCryptoService.getSafetyNumber();

      state = state.copyWith(
        isLoading: false,
        isPaired: true,
        peerUid: peerUid,
        safetyNumber: sn,
        successMessage: 'Paired successfully with device $peerUid! Public keys stored.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Pairing failed: $e',
      );
      return false;
    }
  }

  /// Regenerate pairing code and publish a fresh beacon
  Future<void> refreshCode() async {
    final newCode = SignalCryptoService.generateRandomPairingCode();
    state = state.copyWith(myPairingCode: newCode, errorMessage: null);
    await publishBeacon(newCode);
  }

  /// Wipe all local secure keys, messages, and reset pairing state
  Future<void> unpairAndReset() async {
    _cleanupRealtime();
    await SecureKeyStorage.clearAll();
    await LocalDatabaseService.clearAllMessages();
    await init();
  }
}

final pairingProvider = NotifierProvider<PairingNotifier, PairingState>(PairingNotifier.new);
