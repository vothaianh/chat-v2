import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';

/// Local, on-device message history (SQLite). The backend never persists
/// messages — this cache is purely client-side so a user can reopen the app
/// and read past conversations. Scoped per-account via a separate DB file.
class MessageStore {
  Database? _db;
  String? _accountId;

  bool get isOpen => _db != null;

  /// Open (or create) the DB for the given account id. Re-opens if the account
  /// changed (e.g. a different user logs in on the same device).
  Future<void> open(String accountId) async {
    if (_db != null && _accountId == accountId) return;
    await close();
    _accountId = accountId;
    final dir = await getDatabasesPath();
    // One DB file per account keeps histories isolated between users.
    final path = p.join(dir, 'chat_messages_$accountId.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            conversationId TEXT NOT NULL,
            type TEXT NOT NULL,
            text TEXT,
            media TEXT,
            caption TEXT,
            senderId TEXT NOT NULL,
            senderUsername TEXT,
            senderFullName TEXT,
            createdAt INTEGER NOT NULL,
            delivered INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_messages_conv ON messages(conversationId, createdAt)');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _accountId = null;
  }

  /// Insert or update a message (id is the primary key → idempotent replays).
  Future<void> upsert(ChatMessage m) async {
    final db = _db;
    if (db == null) return;
    await db.insert(
      'messages',
      m.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load a conversation's history, oldest → newest.
  Future<List<ChatMessage>> loadConversation(String conversationId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  /// The most recent message per conversation — used for chat-list previews.
  Future<Map<String, ChatMessage>> latestPerConversation() async {
    final db = _db;
    if (db == null) return {};
    final rows = await db.rawQuery('''
      SELECT m.* FROM messages m
      JOIN (
        SELECT conversationId, MAX(createdAt) AS mx
        FROM messages GROUP BY conversationId
      ) t ON t.conversationId = m.conversationId AND t.mx = m.createdAt
    ''');
    final out = <String, ChatMessage>{};
    for (final r in rows) {
      final msg = ChatMessage.fromMap(r);
      out[msg.conversationId] = msg;
    }
    return out;
  }

  /// Mark a previously-optimistic message as delivered (after server ack).
  Future<void> markDelivered(String conversationId, String id) async {
    final db = _db;
    if (db == null) return;
    await db.update(
      'messages',
      {'delivered': 1},
      where: 'id = ? AND conversationId = ?',
      whereArgs: [id, conversationId],
    );
  }

  /// Wipe a single conversation's local history.
  Future<void> clearConversation(String conversationId) async {
    await _db?.delete('messages',
        where: 'conversationId = ?', whereArgs: [conversationId]);
  }

  /// Wipe everything (e.g. on account deletion). Logout keeps history so the
  /// user still sees it after signing back in.
  Future<void> clearAll() async {
    await _db?.delete('messages');
  }
}
