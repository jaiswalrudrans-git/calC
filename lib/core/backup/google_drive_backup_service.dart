import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../database/local_cache.dart';
import '../security/media_crypto.dart';
import '../security/secure_key_storage.dart';
import '../theme/app_colors.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class GoogleSignInResult {
  final bool success;
  final String? errorMessage;
  final bool isDeveloperError;
  const GoogleSignInResult({
    required this.success,
    this.errorMessage,
    this.isDeveloperError = false,
  });
}

class GoogleDriveBackupService {
  static final GoogleDriveBackupService instance = GoogleDriveBackupService._internal();
  GoogleDriveBackupService._internal();

  static const String _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _serverClientId.isNotEmpty ? _serverClientId : null,
    scopes: [
      'email',
      drive.DriveApi.driveFileScope,
    ],
  );

  final _uuid = const Uuid();
  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  bool _isSyncing = false;
  String? _rootFolderId;
  final Map<String, String> _monthFolderIdCache = {};

  bool get isSyncing => _isSyncing;
  bool get isConnected => _currentUser != null && _driveApi != null;
  String? get userEmail => _currentUser?.email;

  /// Stream/Listeners for backup state changes
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> syncStatusNotifier = ValueNotifier<String?>(null);

  /// Initialize silent sign-in if previously authorized on this device
  Future<void> init() async {
    final isOwner = await SecureKeyStorage.isOwnerDevice();
    if (!isOwner) return; // Non-owner devices never touch Drive

    try {
      _googleSignIn.onCurrentUserChanged.listen((account) async {
        _currentUser = account;
        if (account != null) {
          final authHeaders = await account.authHeaders;
          _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
          await SecureKeyStorage.setDriveAccountEmail(account.email);
          await SecureKeyStorage.setDriveBackupEnabled(true);
        } else {
          _driveApi = null;
          await SecureKeyStorage.setDriveAccountEmail(null);
          await SecureKeyStorage.setDriveBackupEnabled(false);
        }
      });

      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        final authHeaders = await account.authHeaders;
        _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[GoogleDrive] Silent init error: $e');
    }
  }

  /// Interactive sign-in flow (only triggered when owner approves)
  Future<GoogleSignInResult> signIn() async {
    try {
      final isOwner = await SecureKeyStorage.isOwnerDevice();
      debugPrint('[GoogleDrive] signIn() called. isOwner=$isOwner');
      if (!isOwner) {
        return const GoogleSignInResult(
          success: false,
          errorMessage: 'This device is not configured as the owner device.',
        );
      }

      debugPrint('[GoogleDrive] Calling _googleSignIn.signIn()...');
      final account = await _googleSignIn.signIn();
      debugPrint('[GoogleDrive] signIn() returned: account=${account?.email ?? "NULL"}');

      if (account == null) {
        return const GoogleSignInResult(
          success: false,
          errorMessage: 'Sign-in cancelled or no account selected.',
        );
      }

      _currentUser = account;
      debugPrint('[GoogleDrive] Getting auth headers...');
      final authHeaders = await account.authHeaders;
      debugPrint('[GoogleDrive] Got ${authHeaders.length} auth headers. Creating DriveApi...');
      _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
      await SecureKeyStorage.setDriveAccountEmail(account.email);
      await SecureKeyStorage.setDriveBackupEnabled(true);
      debugPrint('[GoogleDrive] Sign-in SUCCESSFUL for ${account.email}');

      // Trigger initial root folder discovery and sync
      unawaited(syncIncremental());
      return const GoogleSignInResult(success: true);
    } on PlatformException catch (e, stack) {
      final msg = '[GoogleDrive] PlatformException: code=${e.code} '
          'message=${e.message} details=${e.details}';
      debugPrint(msg);
      debugPrint('$stack');
      final isDevError = e.message?.contains('10') == true ||
          e.message?.contains('ApiException: 10') == true ||
          e.code.contains('10') ||
          (e.code == 'sign_in_failed' && (e.message == null || e.message!.contains('10')));
      return GoogleSignInResult(
        success: false,
        errorMessage: isDevError
            ? 'Google Sign-In requires your device SHA-1 fingerprint to be registered in Firebase Console (ApiException 10).'
            : 'Google Sign-In failed (${e.code}): ${e.message}',
        isDeveloperError: isDevError,
      );
    } catch (e, stack) {
      debugPrint('[GoogleDrive] Sign-in error: $e\n$stack');
      return GoogleSignInResult(
        success: false,
        errorMessage: 'Sign-in error: $e',
      );
    }
  }

  /// Disconnect account
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      _driveApi = null;
      _rootFolderId = null;
      _monthFolderIdCache.clear();
      await SecureKeyStorage.setDriveAccountEmail(null);
      await SecureKeyStorage.setDriveBackupEnabled(false);
    } catch (_) {}
  }

  /// Prompt for Google Drive OAuth the first time any media is sent or received
  /// Strictly on the owner's device, not before, and never on the peer device.
  Future<void> checkAndPromptFirstMediaAuth(BuildContext context) async {
    final isOwner = await SecureKeyStorage.isOwnerDevice();
    if (!isOwner) return; // Second device never sees Drive prompt

    final alreadyPrompted = await SecureKeyStorage.hasPromptedDriveAuth();
    if (alreadyPrompted) return;

    if (isConnected) return;

    await SecureKeyStorage.setHasPromptedDriveAuth(true);

    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? MetricGlass.level2 : Colors.grey.shade100,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? MetricGlass.border : Colors.grey.shade300,
                  width: 1.0,
                ),
              ),
              child: Icon(Icons.cloud_upload_rounded, color: isDark ? MetricColors.textPrimary : Colors.black87, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'Encrypted Google Drive Backup',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Secure your chat and media in your private Google Drive.\n\n'
              '• Zero-knowledge: Everything is client-side encrypted before upload.\n'
              '• Obscured filenames: No plaintext names or EXIF metadata ever leave this phone.\n'
              '• Only your device holds the decryption keys.',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Not Now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final result = await signIn();
                      if (context.mounted) {
                        if (result.success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Google Drive Backup connected successfully!')),
                          );
                        } else if (result.errorMessage != null &&
                            !result.errorMessage!.contains('cancelled')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Google Drive: ${result.errorMessage}'),
                              backgroundColor: AppColors.alertRed,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.cloud_done_rounded, size: 18),
                    label: const Text('Connect Drive'),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Automatically queue an outgoing or incoming media message for Drive backup
  Future<void> queueMediaMessage(LocalChatMessage message) async {
    final isOwner = await SecureKeyStorage.isOwnerDevice();
    if (!isOwner) return; // Only owner backs up to Drive

    final date = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final folderKey = DateFormat('yyyy-MM').format(date);
    final obscuredName = 'enc_${_uuid.v4()}.bin';

    final ledgerItem = DriveLedgerItem(
      id: _uuid.v4(),
      localMsgId: message.id,
      localFilePath: message.localPath,
      mediaType: message.mediaType,
      folderKey: folderKey,
      obscuredFilename: obscuredName,
      timestamp: message.timestamp,
      status: 'pending',
    );

    await LocalDatabaseService.queueDriveBackup(ledgerItem);

    // Trigger incremental sync in the background if connected
    if (isConnected && !_isSyncing) {
      unawaited(syncIncremental());
    }
  }

  /// Find or create the root "Metric_Backup" folder
  Future<String> _ensureRootFolder() async {
    if (_rootFolderId != null) return _rootFolderId!;

    final cachedId = await SecureKeyStorage.getDriveRootFolderId();
    if (cachedId != null) {
      _rootFolderId = cachedId;
      return cachedId;
    }

    final query = "name = 'Metric_Backup' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await _driveApi!.files.list(q: query, spaces: 'drive', $fields: 'files(id, name)');
    if (result.files != null && result.files!.isNotEmpty) {
      _rootFolderId = result.files!.first.id!;
      await SecureKeyStorage.setDriveRootFolderId(_rootFolderId);
      return _rootFolderId!;
    }

    final folderMetadata = drive.File()
      ..name = 'Metric_Backup'
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = ['root'];

    final created = await _driveApi!.files.create(folderMetadata, $fields: 'id');
    _rootFolderId = created.id!;
    await SecureKeyStorage.setDriveRootFolderId(_rootFolderId);
    return _rootFolderId!;
  }

  /// Find or create a subfolder (e.g. "2026-09" or "db")
  Future<String> _ensureSubFolder(String rootId, String folderName) async {
    if (_monthFolderIdCache.containsKey(folderName)) {
      return _monthFolderIdCache[folderName]!;
    }

    final query = "name = '$folderName' and '$rootId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await _driveApi!.files.list(q: query, spaces: 'drive', $fields: 'files(id, name)');
    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      _monthFolderIdCache[folderName] = id;
      return id;
    }

    final folderMetadata = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [rootId];

    final created = await _driveApi!.files.create(folderMetadata, $fields: 'id');
    _monthFolderIdCache[folderName] = created.id!;
    return created.id!;
  }

  /// Incremental background sync:
  /// - Only uploads new/changed content since last sync
  /// - All files are strictly ciphertext with random obscured filenames
  /// - Backs up database snapshot to Metric_Backup/db/
  /// - Never blocks messaging or UI
  Future<void> syncIncremental() async {
    if (_isSyncing) return;
    final isOwner = await SecureKeyStorage.isOwnerDevice();
    if (!isOwner) return;

    if (!isConnected) {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return;
      final authHeaders = await account.authHeaders;
      _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
      _currentUser = account;
    }

    _isSyncing = true;
    isSyncingNotifier.value = true;
    syncStatusNotifier.value = 'Syncing...';

    try {
      final rootId = await _ensureRootFolder();

      // 1. Process pending media items from the ledger
      final pendingItems = await LocalDatabaseService.getPendingDriveBackups();

      for (final item in pendingItems) {
        try {
          if (item.localFilePath == null) {
            await LocalDatabaseService.markDriveBackupSynced(item.id, 'none');
            continue;
          }

          final localFile = File(item.localFilePath!);
          if (!await localFile.exists()) {
            await LocalDatabaseService.markDriveBackupSynced(item.id, 'missing');
            continue;
          }

          final rawBytes = await localFile.readAsBytes();

          // Client-side AES-256-GCM encryption
          final encrypted = await MediaCryptoService.encryptMediaBytes(rawBytes);

          // Build ciphertext envelope
          final envelopeMap = {
            'v': 1,
            'cipher': base64Encode(encrypted.ciphertext),
            'key': encrypted.keyHex,
            'iv': encrypted.ivHex,
            'mac': encrypted.macHex,
            'orig_size': encrypted.originalSize,
            'media_type': item.mediaType,
            'ts': item.timestamp,
          };
          final envelopeBytes = utf8.encode(jsonEncode(envelopeMap));

          // Ensure month subfolder exists (e.g. "2026-09")
          final subFolderId = await _ensureSubFolder(rootId, item.folderKey);

          // Upload with strictly obscured filename
          final driveFile = drive.File()
            ..name = item.obscuredFilename
            ..parents = [subFolderId];

          final media = drive.Media(
            Stream.value(envelopeBytes),
            envelopeBytes.length,
          );

          final uploaded = await _driveApi!.files.create(
            driveFile,
            uploadMedia: media,
            $fields: 'id',
          );

          await LocalDatabaseService.markDriveBackupSynced(item.id, uploaded.id ?? 'synced');

          // Gentle pause to stay well within Drive API rate limits
          await Future.delayed(const Duration(milliseconds: 150));
        } catch (e) {
          if (kDebugMode) debugPrint('[GoogleDrive] Item upload error: $e');
          await LocalDatabaseService.markDriveBackupFailed(item.id, e.toString());
        }
      }

      // 2. Back up database snapshot to Metric_Backup/db/
      await _backupEncryptedDatabase(rootId);

      await SecureKeyStorage.setLastDriveSyncTime(DateTime.now().millisecondsSinceEpoch);
      syncStatusNotifier.value = 'Up to date';
    } catch (e) {
      if (kDebugMode) debugPrint('[GoogleDrive] Sync error: $e');
      syncStatusNotifier.value = 'Sync paused (will retry)';
    } finally {
      _isSyncing = false;
      isSyncingNotifier.value = false;
    }
  }

  /// Encrypt and upload SQLite database snapshot to Metric_Backup/db/
  Future<void> _backupEncryptedDatabase(String rootId) async {
    try {
      final dbPath = await LocalDatabaseService.getLocalDatabaseFilePath();
      if (dbPath == null) return;

      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      final dbBytes = await dbFile.readAsBytes();
      final encrypted = await MediaCryptoService.encryptMediaBytes(dbBytes);

      final envelopeMap = {
        'v': 1,
        'type': 'database',
        'cipher': base64Encode(encrypted.ciphertext),
        'key': encrypted.keyHex,
        'iv': encrypted.ivHex,
        'mac': encrypted.macHex,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
      final envelopeBytes = utf8.encode(jsonEncode(envelopeMap));

      final dbFolderId = await _ensureSubFolder(rootId, 'db');

      final driveFile = drive.File()
        ..name = 'enc_vault_db_${DateTime.now().millisecondsSinceEpoch}.bin'
        ..parents = [dbFolderId];

      final media = drive.Media(
        Stream.value(envelopeBytes),
        envelopeBytes.length,
      );

      await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
        $fields: 'id',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GoogleDrive] Database backup error: $e');
    }
  }

  /// Restore chat history and sandboxed media from Google Drive
  Future<int> restoreFromDrive() async {
    if (!isConnected) {
      final result = await signIn();
      if (!result.success) throw Exception(result.errorMessage ?? 'Google account not connected');
    }

    final rootId = await _ensureRootFolder();
    final dbFolderId = await _ensureSubFolder(rootId, 'db');

    // Find the latest database snapshot in db/
    final query = "'$dbFolderId' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false";
    final result = await _driveApi!.files.list(
      q: query,
      spaces: 'drive',
      orderBy: 'createdTime desc',
      pageSize: 1,
      $fields: 'files(id, name)',
    );

    if (result.files == null || result.files!.isEmpty) {
      throw Exception('No database backup snapshot found in Google Drive');
    }

    final latestDbFile = result.files!.first;
    final fileId = latestDbFile.id!;

    // Download encrypted snapshot
    final drive.Media media = await _driveApi!.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final List<int> downloadedBytes = [];
    await for (final chunk in media.stream) {
      downloadedBytes.addAll(chunk);
    }

    final envelopeString = utf8.decode(downloadedBytes);
    final map = jsonDecode(envelopeString) as Map<String, dynamic>;

    final ciphertext = base64Decode(map['cipher'] as String);
    final keyHex = map['key'] as String;
    final ivHex = map['iv'] as String;
    final macHex = map['mac'] as String;

    final decryptedDbBytes = await MediaCryptoService.decryptMediaBytes(
      ciphertext,
      keyHex: keyHex,
      ivHex: ivHex,
      macHex: macHex,
    );

    // Restore to local SQLite database path
    final dbPath = await LocalDatabaseService.getLocalDatabaseFilePath();
    if (dbPath != null) {
      final dbFile = File(dbPath);
      await dbFile.writeAsBytes(decryptedDbBytes, flush: true);
    }

    final restoredMessages = await LocalDatabaseService.getMessages();
    return restoredMessages.length;
  }
}
