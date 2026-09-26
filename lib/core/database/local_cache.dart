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
  final String? mediaType; // 'photo', 'video', 'voice', null
  final String? reaction;

  LocalChatMessage({
    required this.id,
    required this.senderUid,
    required this.receiverUid,
    required this.text,
    required this.timestamp,
    this.expiresAt,
    required this.isMe,
    this.mediaType,
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
      'mediaType': mediaType,
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
      mediaType: map['mediaType'] as String?,
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
        version: 1,
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
              mediaType TEXT,
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
          mediaType TEXT,
          reaction TEXT
        )
      ''');
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
      return db;
    }
  }

  // --- Chat Operations ---
  static Future<void> saveMessage(LocalChatMessage message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
}
