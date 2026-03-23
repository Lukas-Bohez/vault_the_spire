import 'dart:async';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static Database? _database;
  static String? _encryptionKey;

  /// Optionally set a SQLCipher key before opening the DB.
  static void setEncryptionKey(String key) {
    _encryptionKey = key;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = await _getDatabasePath();
    _database = await openDatabase(
      dbPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // Enable foreign keys
        await db.execute('PRAGMA foreign_keys = ON');

        if (_encryptionKey != null && _encryptionKey!.isNotEmpty) {
          await db.execute(
            "PRAGMA key = '${_encryptionKey!.replaceAll("'", "''")}'",
          );

          final cipherRows = await db.rawQuery('PRAGMA cipher_version;');
          final cipherVersion = cipherRows.isNotEmpty
              ? cipherRows.first.values.first?.toString() ?? ''
              : '';
          if (cipherVersion.isEmpty) {
            throw StateError('SQLCipher not loaded — check your dependencies!');
          }
        }
      },
    );
    return _database!;
  }

  Future<String> _getDatabasePath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, 'vault_the_spire.db');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE torrents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        total_size INTEGER,
        total_pieces INTEGER,
        piece_length INTEGER,
        pieces_have TEXT,
        status TEXT,
        type TEXT NOT NULL,
        vault_key TEXT,
        file_path TEXT,
        vault_link TEXT,
        magnet_link TEXT,
        bytes_down INTEGER DEFAULT 0,
        bytes_up INTEGER DEFAULT 0,
        added_at INTEGER,
        completed_at INTEGER,
        is_sequential INTEGER DEFAULT 0,
        selected_files TEXT,
        max_seed_ratio REAL,
        delete_after_ratio_reached INTEGER DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        recipient TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_sent INTEGER NOT NULL DEFAULT 0,
        protocol TEXT NOT NULL DEFAULT 'local'
      );
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE torrents ADD COLUMN max_seed_ratio REAL;
      ''');
      await db.execute('''
        ALTER TABLE torrents ADD COLUMN delete_after_ratio_reached INTEGER DEFAULT 0;
      ''');
    }
  }

    await db.execute('''
      CREATE TABLE servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        icon TEXT,
        channels TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        server_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        author TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY(server_id) REFERENCES servers(id) ON DELETE CASCADE
      );
    ''');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
