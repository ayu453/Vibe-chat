import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/mesh_envelope.dart';

/// Durable SQLite carrier queue. It stores only opaque envelopes.
class SqliteMeshOutbox {
  SqliteMeshOutbox({this.maxBytes = 20 * 1024 * 1024});
  final int maxBytes;
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(p.join(root, 'vibe_mesh.db'), version: 1,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE envelopes (
          id TEXT PRIMARY KEY, tag TEXT NOT NULL, payload TEXT NOT NULL,
          created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
          byte_size INTEGER NOT NULL
        )''');
        await db.execute('CREATE INDEX idx_mesh_tag_expiry ON envelopes(tag, expires_at)');
        await db.execute('CREATE INDEX idx_mesh_created ON envelopes(created_at)');
      });
    return _db!;
  }

  Future<void> pruneExpired({int? nowMs}) async {
    final db = await database;
    await db.delete('envelopes', where: 'expires_at <= ?',
      whereArgs: [nowMs ?? DateTime.now().millisecondsSinceEpoch]);
  }

  Future<bool> store(MeshEnvelope envelope, {int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    envelope.validate(nowMs: now);
    final payload = envelope.encode();
    final bytes = utf8.encode(payload).length;
    if (bytes > maxBytes) return false;
    final db = await database;
    await pruneExpired(nowMs: now);
    final existing = await db.query('envelopes', columns: ['id'],
      where: 'id = ?', whereArgs: [envelope.id], limit: 1);
    if (existing.isNotEmpty) return false;
    final total = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COALESCE(SUM(byte_size), 0) FROM envelopes')) ?? 0;
    var remaining = total;
    while (remaining + bytes > maxBytes) {
      final oldest = await db.query('envelopes', columns: ['id', 'byte_size'],
        orderBy: 'created_at ASC', limit: 1);
      if (oldest.isEmpty) return false;
      remaining -= oldest.first['byte_size'] as int;
      await db.delete('envelopes', where: 'id = ?', whereArgs: [oldest.first['id']]);
    }
    await db.insert('envelopes', {
      'id': envelope.id, 'tag': envelope.tag, 'payload': payload,
      'created_at': envelope.createdAt, 'expires_at': envelope.expiresAt,
      'byte_size': bytes,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  Future<List<MeshEnvelope>> forTags(Iterable<String> tags, {int? nowMs}) async {
    final list = tags.toSet().toList();
    if (list.isEmpty) return const [];
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final db = await database;
    await pruneExpired(nowMs: now);
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.query('envelopes',
      where: 'tag IN ($placeholders) AND expires_at > ?',
      whereArgs: [...list, now], orderBy: 'created_at ASC');
    return rows.map((row) => MeshEnvelope.fromJson(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>)).toList();
  }

  Future<List<MeshEnvelope>> all({int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final db = await database;
    await pruneExpired(nowMs: now);
    final rows = await db.query('envelopes',
      where: 'expires_at > ?', whereArgs: [now], orderBy: 'created_at ASC');
    return rows.map((row) => MeshEnvelope.fromJson(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>)).toList();
  }

  Future<void> replace(MeshEnvelope envelope, {int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    envelope.validate(nowMs: now);
    final payload = envelope.encode();
    await (await database).update('envelopes', {
      'payload': payload,
      'created_at': envelope.createdAt,
      'expires_at': envelope.expiresAt,
      'byte_size': utf8.encode(payload).length,
    }, where: 'id = ?', whereArgs: [envelope.id]);
  }

  Future<void> remove(String id) async =>
      (await database).delete('envelopes', where: 'id = ?', whereArgs: [id]);

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
