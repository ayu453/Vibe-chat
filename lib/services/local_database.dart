import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/chat_message.dart';

class LocalDatabase {
  Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(p.join(root, 'vibe_chat.db'), version: 2,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE messages (
          id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, sender_id TEXT NOT NULL,
          body TEXT NOT NULL, mood_id TEXT NOT NULL, sound_id TEXT NOT NULL,
          created_at TEXT NOT NULL, is_outgoing INTEGER NOT NULL, status TEXT NOT NULL
        )''');
        await db.execute('CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE messages ADD COLUMN sound_id TEXT NOT NULL DEFAULT 'neutral'");
          await db.execute("ALTER TABLE messages ADD COLUMN status TEXT NOT NULL DEFAULT 'sent'");
          await db.execute('UPDATE messages SET sound_id = mood_id');
        }
      });
    return _database!;
  }
  Future<void> insertMessage(ChatMessage message) async {
    await (await database).insert('messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  Future<void> updateStatus(String id, String status) async {
    await (await database).update('messages', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }
  Future<List<ChatMessage>> messagesFor(String conversationId) async {
    final rows = await (await database).query('messages', where: 'conversation_id = ?',
      whereArgs: [conversationId], orderBy: 'created_at ASC');
    return rows.map(ChatMessage.fromMap).toList();
  }
  Future<List<Map<String, Object?>>> conversations() async {
    return (await database).rawQuery('''SELECT conversation_id, body, created_at, mood_id
      FROM messages m WHERE created_at = (
        SELECT MAX(created_at) FROM messages WHERE conversation_id = m.conversation_id
      ) ORDER BY created_at DESC''');
  }
}
