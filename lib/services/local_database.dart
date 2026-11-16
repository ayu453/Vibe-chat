import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/chat_message.dart';

class LocalDatabase {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      p.join(root, 'vibe_chat.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            body TEXT NOT NULL,
            mood_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            is_outgoing INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at)');
      },
    );
    return _database!;
  }

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert('messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<ChatMessage>> messagesFor(String conversationId) async {
    final db = await database;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> conversations() async {
    final db = await database;
    return db.rawQuery('''
      SELECT conversation_id, body, created_at, mood_id
      FROM messages m
      WHERE created_at = (
        SELECT MAX(created_at) FROM messages
        WHERE conversation_id = m.conversation_id
      )
      ORDER BY created_at DESC
    ''');
  }
}
