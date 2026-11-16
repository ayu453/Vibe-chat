import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/chat_message.dart';

class LocalDatabase {
  Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(p.join(root, 'vibe_chat.db'), version: 3,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE messages (
          id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, sender_id TEXT NOT NULL,
          body TEXT NOT NULL, mood_id TEXT NOT NULL, sound_id TEXT NOT NULL,
          created_at TEXT NOT NULL, is_outgoing INTEGER NOT NULL, status TEXT NOT NULL
        )''');
        await db.execute('CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at)');
        await db.execute(_contactsSql);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE messages ADD COLUMN sound_id TEXT NOT NULL DEFAULT 'neutral'");
          await db.execute("ALTER TABLE messages ADD COLUMN status TEXT NOT NULL DEFAULT 'sent'");
          await db.execute('UPDATE messages SET sound_id = mood_id');
        }
        if (oldVersion < 3) await db.execute(_contactsSql);
      });
    return _database!;
  }

  static const _contactsSql = '''CREATE TABLE contacts (
    id TEXT PRIMARY KEY, username TEXT NOT NULL, signing_public_key TEXT NOT NULL,
    encryption_public_key TEXT NOT NULL, encryption_key_signature TEXT NOT NULL,
    relay_url TEXT NOT NULL, status TEXT NOT NULL, direction TEXT NOT NULL,
    key_changed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL,
    pending_signing_public_key TEXT, pending_encryption_public_key TEXT,
    pending_encryption_key_signature TEXT
  )''';

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
    return (await database).rawQuery('''SELECT m.conversation_id, m.body, m.created_at, m.mood_id
      FROM messages m INNER JOIN contacts c ON c.id = m.conversation_id AND c.status = 'accepted'
      WHERE m.created_at = (
        SELECT MAX(m2.created_at) FROM messages m2 WHERE m2.conversation_id = m.conversation_id
      ) ORDER BY m.created_at DESC''');
  }
  Future<void> saveContact({
    required String id, required String username, required String signingPublicKey,
    required String encryptionPublicKey, required String encryptionKeySignature,
    required String relayUrl, required String status, required String direction,
  }) async {
    await (await database).insert('contacts', {
      'id': id, 'username': username, 'signing_public_key': signingPublicKey,
      'encryption_public_key': encryptionPublicKey,
      'encryption_key_signature': encryptionKeySignature, 'relay_url': relayUrl,
      'status': status, 'direction': direction, 'key_changed': 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<Map<String, Object?>>> contacts({String? status}) async {
    return (await database).query('contacts',
      where: status == null ? null : 'status = ?', whereArgs: status == null ? null : [status],
      orderBy: 'username COLLATE NOCASE');
  }
  Future<Map<String, Object?>?> contact(String id) async {
    final rows = await (await database).query('contacts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }
  Future<void> setContactStatus(String id, String status) async {
    await (await database).update('contacts', {
      'status': status, 'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> markContactKeyChanged(String id, {
    required String signingPublicKey, required String encryptionPublicKey,
    required String encryptionKeySignature,
  }) async {
    await (await database).update('contacts', {
      'key_changed': 1, 'pending_signing_public_key': signingPublicKey,
      'pending_encryption_public_key': encryptionPublicKey,
      'pending_encryption_key_signature': encryptionKeySignature,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> confirmContactKey(String id) async {
    final db = await database;
    await db.rawUpdate('''UPDATE contacts SET
      signing_public_key = pending_signing_public_key,
      encryption_public_key = pending_encryption_public_key,
      encryption_key_signature = pending_encryption_key_signature,
      pending_signing_public_key = NULL, pending_encryption_public_key = NULL,
      pending_encryption_key_signature = NULL, key_changed = 0,
      updated_at = ? WHERE id = ?''', [DateTime.now().toIso8601String(), id]);
  }
  Future<void> deleteContact(String id) async {
    final db = await database;
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);
    await db.delete('messages', where: 'conversation_id = ?', whereArgs: [id]);
  }
  Future<bool> isBlocked(String id) async {
    final rows = await (await database).query('contacts', columns: ['id'],
      where: "id = ? AND status = 'blocked'", whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }
}
