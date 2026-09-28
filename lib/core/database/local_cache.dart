import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

class LocalChatMessage {
  final String id;
  final String senderUid;
  final String receiverUid;
  final String text;
  final int timestamp;
  final int? expiresAt;
  final bool isMe;
  final String status; // 'sending', 'sent', 'delivered', 'read', 'failed'
  final String? mediaType; // 'image', 'video', 'voice', 'document', null
  final String? localPath;
  final int? mediaSize;
  final int? duration;
  final String? reaction;

  LocalChatMessage({
    required this.id,
    required this.senderUid,
    required this.receiverUid,
    required this.text,
    required this.timestamp,
    this.expiresAt,
    required this.isMe,
    this.status = 'sent',
    this.mediaType,
    this.localPath,
    this.mediaSize,
    this.duration,
    this.reaction,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderUid': senderUid,
      'receiverUid': receiverUid,
      'text': text,
      'timestamp': timestamp,
      'expiresAt': expiresAt,
      'isMe': isMe ? 1 : 0,
      'status': status,
      'mediaType': mediaType,
      'localPath': localPath,
      'mediaSize': mediaSize,
      'duration': duration,
      'reaction': reaction,
    };
  }

  factory LocalChatMessage.fromMap(Map<String, dynamic> map) {
    return LocalChatMessage(
      id: map['id'] as String,
      senderUid: map['senderUid'] as String,
      receiverUid: map['receiverUid'] as String,
      text: map['text'] as String,
      timestamp: map['timestamp'] as int,
      expiresAt: map['expiresAt'] as int?,
      isMe: (map['isMe'] as int) == 1,
      status: map['status'] as String? ?? 'sent',
      mediaType: map['mediaType'] as String?,
      localPath: map['localPath'] as String?,
      mediaSize: (map['mediaSize'] as num?)?.toInt(),
      duration: (map['duration'] as num?)?.toInt(),
      reaction: map['reaction'] as String?,
    );
  }
}

class ConversionRecord {
  final String id;
  final String category;
  final String fromUnit;
  final String toUnit;
  final double fromValue;
  final double toValue;
  final int timestamp;
  final bool isFavorite;

  ConversionRecord({
    required this.id,
    required this.category,
    required this.fromUnit,
    required this.toUnit,
    required this.fromValue,
    required this.toValue,
    required this.timestamp,
    this.isFavorite = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'fromUnit': fromUnit,
      'toUnit': toUnit,
      'fromValue': fromValue,
      'toValue': toValue,
      'timestamp': timestamp,
      'isFavorite': isFavorite ? 1 : 0,
    };
  }

  factory ConversionRecord.fromMap(Map<String, dynamic> map) {
    return ConversionRecord(
      id: map['id'] as String,
      category: map['category'] as String,
      fromUnit: map['fromUnit'] as String,
      toUnit: map['toUnit'] as String,
      fromValue: (map['fromValue'] as num).toDouble(),
      toValue: (map['toValue'] as num).toDouble(),
      timestamp: map['timestamp'] as int,
      isFavorite: (map['isFavorite'] as int) == 1,
    );
  }
}

class DriveLedgerItem {
  final String id;
  final String localMsgId;
  final String? localFilePath;
  final String? mediaType;
  final String folderKey; // e.g. "2026-09" or "db"
  final String obscuredFilename;
  final String? driveFileId;
  final String status; // 'pending', 'synced', 'failed'
  final int timestamp;
  final int? syncedAt;
  final String? error;

  DriveLedgerItem({
    required this.id,
    required this.localMsgId,
    this.localFilePath,
    this.mediaType,
    required this.folderKey,
    required this.obscuredFilename,
    this.driveFileId,
    this.status = 'pending',
    required this.timestamp,
    this.syncedAt,
    this.error,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'local_msg_id': localMsgId,
    'local_file_path': localFilePath,
    'media_type': mediaType,
    'folder_key': folderKey,
    'obscured_filename': obscuredFilename,
    'drive_file_id': driveFileId,
    'status': status,
    'timestamp': timestamp,
    'synced_at': syncedAt,
    'error': error,
  };

  factory DriveLedgerItem.fromMap(Map<String, dynamic> map) => DriveLedgerItem(
    id: map['id'] as String,
    localMsgId: map['local_msg_id'] as String,
    localFilePath: map['local_file_path'] as String?,
    mediaType: map['media_type'] as String?,
    folderKey: map['folder_key'] as String,
    obscuredFilename: map['obscured_filename'] as String,
    driveFileId: map['drive_file_id'] as String?,
    status: map['status'] as String? ?? 'pending',
    timestamp: (map['timestamp'] as num).toInt(),
    syncedAt: (map['synced_at'] as num?)?.toInt(),
    error: map['error'] as String?,
  );
}

class LocalDatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    try {
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'metric_local_vault.db');

      return await openDatabase(
        path,
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE messages (
              id TEXT PRIMARY KEY,
              senderUid TEXT,
              receiverUid TEXT,
              text TEXT,
              timestamp INTEGER,
              expiresAt INTEGER,
              isMe INTEGER,
              status TEXT DEFAULT 'sent',
              mediaType TEXT,
              localPath TEXT,
              mediaSize INTEGER,
              duration INTEGER,
              reaction TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE conversions (
              id TEXT PRIMARY KEY,
              category TEXT,
              fromUnit TEXT,
              toUnit TEXT,
              fromValue REAL,
              toValue REAL,
              timestamp INTEGER,
              isFavorite INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE drive_backup_ledger (
              id TEXT PRIMARY KEY,
              local_msg_id TEXT,
              local_file_path TEXT,
              media_type TEXT,
              folder_key TEXT,
              obscured_filename TEXT,
              drive_file_id TEXT,
              status TEXT DEFAULT 'pending',
              timestamp INTEGER,
              synced_at INTEGER,
              error TEXT
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          try { await db.execute('ALTER TABLE messages ADD COLUMN status TEXT DEFAULT "sent"'); } catch (_) {}
          try { await db.execute('ALTER TABLE messages ADD COLUMN localPath TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE messages ADD COLUMN mediaSize INTEGER'); } catch (_) {}
          try { await db.execute('ALTER TABLE messages ADD COLUMN duration INTEGER'); } catch (_) {}
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS drive_backup_ledger (
                id TEXT PRIMARY KEY,
                local_msg_id TEXT,
                local_file_path TEXT,
                media_type TEXT,
                folder_key TEXT,
                obscured_filename TEXT,
                drive_file_id TEXT,
                status TEXT DEFAULT 'pending',
                timestamp INTEGER,
                synced_at INTEGER,
                error TEXT
              )
            ''');
          } catch (_) {}
        },
        onOpen: (db) async {
          try { await db.execute('ALTER TABLE messages ADD COLUMN status TEXT DEFAULT "sent"'); } catch (_) {}
          try { await db.execute('ALTER TABLE messages ADD COLUMN localPath TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE messages ADD COLUMN mediaSize INTEGER'); } catch (_) {}
          try { await db.execute('ALTER TABLE messages ADD COLUMN duration INTEGER'); } catch (_) {}
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS drive_backup_ledger (
                id TEXT PRIMARY KEY,
                local_msg_id TEXT,
                local_file_path TEXT,
                media_type TEXT,
                folder_key TEXT,
                obscured_filename TEXT,
                drive_file_id TEXT,
                status TEXT DEFAULT 'pending',
                timestamp INTEGER,
                synced_at INTEGER,
                error TEXT
              )
            ''');
          } catch (_) {}
        },
      );
    } catch (_) {
      // In-memory robust fallback for environments without file system write permission
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          id TEXT PRIMARY KEY,
          senderUid TEXT,
          receiverUid TEXT,
          text TEXT,
          timestamp INTEGER,
          expiresAt INTEGER,
          isMe INTEGER,
          status TEXT DEFAULT 'sent',
          mediaType TEXT,
          localPath TEXT,
          mediaSize INTEGER,
          duration INTEGER,
          reaction TEXT
        )
      ''');
      try { await db.execute('ALTER TABLE messages ADD COLUMN status TEXT DEFAULT "sent"'); } catch (_) {}
      try { await db.execute('ALTER TABLE messages ADD COLUMN localPath TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE messages ADD COLUMN mediaSize INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE messages ADD COLUMN duration INTEGER'); } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS conversions (
          id TEXT PRIMARY KEY,
          category TEXT,
          fromUnit TEXT,
          toUnit TEXT,
          fromValue REAL,
          toValue REAL,
          timestamp INTEGER,
          isFavorite INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS drive_backup_ledger (
          id TEXT PRIMARY KEY,
          local_msg_id TEXT,
          local_file_path TEXT,
          media_type TEXT,
          folder_key TEXT,
          obscured_filename TEXT,
          drive_file_id TEXT,
          status TEXT DEFAULT 'pending',
          timestamp INTEGER,
          synced_at INTEGER,
          error TEXT
        )
      ''');
      return db;
    }
  }

  static Future<void> saveMessage(LocalChatMessage message) async {
    final db = await database;
    try {
      await db.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      try { await db.execute('ALTER TABLE messages ADD COLUMN status TEXT DEFAULT "sent"'); } catch (_) {}
      try { await db.execute('ALTER TABLE messages ADD COLUMN localPath TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE messages ADD COLUMN mediaSize INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE messages ADD COLUMN duration INTEGER'); } catch (_) {}
      await db.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  static Future<LocalChatMessage?> getMessageById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return LocalChatMessage.fromMap(maps.first);
  }

  static Future<List<LocalChatMessage>> getMessages() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.delete('messages', where: 'expiresAt IS NOT NULL AND expiresAt < ?', whereArgs: [now]);

    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => LocalChatMessage.fromMap(m)).toList();
  }

  static Future<List<LocalChatMessage>> getMessagesForPeer(String peerUid, {String? myUid}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.delete('messages', where: 'expiresAt IS NOT NULL AND expiresAt < ?', whereArgs: [now]);

    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'senderUid = ? OR receiverUid = ?',
      whereArgs: [peerUid, peerUid],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) {
      final sender = m['senderUid'] as String;
      final isMe = (myUid != null && myUid.isNotEmpty)
          ? sender == myUid
          : (m['isMe'] as int) == 1;
      return LocalChatMessage(
        id: m['id'] as String,
        senderUid: sender,
        receiverUid: m['receiverUid'] as String,
        text: m['text'] as String,
        timestamp: m['timestamp'] as int,
        expiresAt: m['expiresAt'] as int?,
        isMe: isMe,
        status: m['status'] as String? ?? 'sent',
        mediaType: m['mediaType'] as String?,
        localPath: m['localPath'] as String?,
        mediaSize: (m['mediaSize'] as num?)?.toInt(),
        duration: (m['duration'] as num?)?.toInt(),
        reaction: m['reaction'] as String?,
      );
    }).toList();
  }

  static Future<LocalChatMessage?> getLastMessageForPeer(String peerUid, {String? myUid}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'senderUid = ? OR receiverUid = ?',
      whereArgs: [peerUid, peerUid],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final m = maps.first;
    final sender = m['senderUid'] as String;
    final isMe = (myUid != null && myUid.isNotEmpty)
        ? sender == myUid
        : (m['isMe'] as int) == 1;
    return LocalChatMessage(
      id: m['id'] as String,
      senderUid: sender,
      receiverUid: m['receiverUid'] as String,
      text: m['text'] as String,
      timestamp: m['timestamp'] as int,
      expiresAt: m['expiresAt'] as int?,
      isMe: isMe,
      status: m['status'] as String? ?? 'sent',
      mediaType: m['mediaType'] as String?,
      localPath: m['localPath'] as String?,
      mediaSize: (m['mediaSize'] as num?)?.toInt(),
      duration: (m['duration'] as num?)?.toInt(),
      reaction: m['reaction'] as String?,
    );
  }

  static Future<void> updateMessageStatus(String messageId, String status) async {
    final db = await database;
    if (status == 'delivered') {
      await db.update(
        'messages',
        {'status': status},
        where: 'id = ? AND status != "read"',
        whereArgs: [messageId],
      );
    } else {
      await db.update('messages', {'status': status}, where: 'id = ?', whereArgs: [messageId]);
    }
  }

  static Future<void> markAllSentMessagesAsRead(String peerUid) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': 'read'},
      where: 'isMe = 1 AND receiverUid = ? AND status != "read"',
      whereArgs: [peerUid],
    );
  }

  static Future<void> markAllSentMessagesAsDelivered(String peerUid) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': 'delivered'},
      where: 'isMe = 1 AND receiverUid = ? AND status = "sent"',
      whereArgs: [peerUid],
    );
  }

  static Future<void> updateReaction(String messageId, String? reaction) async {
    final db = await database;
    await db.update('messages', {'reaction': reaction}, where: 'id = ?', whereArgs: [messageId]);
  }

  static Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  static Future<void> clearAllMessages() async {
    final db = await database;
    await db.delete('messages');
  }

  // --- Conversion History & Favorites Operations ---
  static Future<void> recordConversion(ConversionRecord record) async {
    final db = await database;
    await db.insert('conversions', record.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<ConversionRecord>> getConversionHistory({int limit = 50}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'conversions',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => ConversionRecord.fromMap(m)).toList();
  }

  static Future<List<ConversionRecord>> getFavorites() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'conversions',
      where: 'isFavorite = 1',
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => ConversionRecord.fromMap(m)).toList();
  }

  static Future<void> toggleFavorite(String id, bool isFavorite) async {
    final db = await database;
    await db.update('conversions', {'isFavorite': isFavorite ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearConversions() async {
    final db = await database;
    await db.delete('conversions');
  }

  // --- Google Drive Backup Ledger Operations ---
  static Future<void> queueDriveBackup(DriveLedgerItem item) async {
    final db = await database;
    await db.insert('drive_backup_ledger', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<DriveLedgerItem>> getPendingDriveBackups() async {
    final db = await database;
    final rows = await db.query(
      'drive_backup_ledger',
      where: "status != 'synced'",
      orderBy: 'timestamp ASC',
    );
    return rows.map((r) => DriveLedgerItem.fromMap(r)).toList();
  }

  static Future<void> markDriveBackupSynced(String id, String driveFileId) async {
    final db = await database;
    await db.update(
      'drive_backup_ledger',
      {
        'drive_file_id': driveFileId,
        'status': 'synced',
        'synced_at': DateTime.now().millisecondsSinceEpoch,
        'error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markDriveBackupFailed(String id, String error) async {
    final db = await database;
    await db.update(
      'drive_backup_ledger',
      {
        'status': 'failed',
        'error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<DriveLedgerItem>> getAllDriveLedger() async {
    final db = await database;
    final rows = await db.query('drive_backup_ledger', orderBy: 'timestamp DESC');
    return rows.map((r) => DriveLedgerItem.fromMap(r)).toList();
  }

  static Future<String?> getLocalDatabaseFilePath() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'metric_local_vault.db');
      final file = File(path);
      if (await file.exists()) {
        return path;
      }
    } catch (_) {}
    return null;
  }
}
