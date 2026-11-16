import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'identity_service.dart';
import 'local_database.dart';

/// User-owned, password-encrypted backup. No network or cloud APIs are used.
class LocalBackupService {
  LocalBackupService({IdentityService? identity, LocalDatabase? database})
      : _identity = identity ?? IdentityService(),
        _database = database ?? LocalDatabase();

  final IdentityService _identity;
  final LocalDatabase _database;
  final Random _random = Random.secure();
  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );
  final AesGcm _cipher = AesGcm.with256bits();

  Future<Uint8List> createBackup(String password) async {
    _validatePassword(password);
    final payload = <String, Object?>{
      'format': 'vibe-chat-local-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'identity': await _identity.exportBackupBundle(),
      'database': await _database.exportSnapshot(),
    };
    final salt = _bytes(16);
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
    );
    final document = {
      'format': 'vibe-chat-encrypted-backup',
      'version': 1,
      'kdf': 'PBKDF2-HMAC-SHA256-120000',
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(document)));
  }

  Future<void> restoreBackup(Uint8List bytes, String password) async {
    _validatePassword(password);
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (document['format'] != 'vibe-chat-encrypted-backup' ||
        document['version'] != 1 ||
        document['kdf'] != 'PBKDF2-HMAC-SHA256-120000' ||
        document['cipher'] != 'AES-256-GCM') {
      throw const FormatException('Unsupported Vibe Chat backup file.');
    }
    final salt = base64Decode(document['salt'] as String);
    final nonce = base64Decode(document['nonce'] as String);
    final cipherText = base64Decode(document['cipherText'] as String);
    final mac = base64Decode(document['mac'] as String);
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    final payload = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    if (payload['format'] != 'vibe-chat-local-backup' || payload['version'] != 1) {
      throw const FormatException('Backup contents are invalid.');
    }
    final identity = payload['identity'];
    final database = payload['database'];
    if (identity is! Map<String, dynamic> || database is! Map<String, dynamic>) {
      throw const FormatException('Backup is missing identity or chat data.');
    }
    // Validate identity keypairs before replacing local data.
    await _identity.restoreBackupBundle(identity);
    await _database.restoreSnapshot(database);
  }

  List<int> _bytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  void _validatePassword(String password) {
    if (password.trim().length < 10) {
      throw ArgumentError('Use a backup password with at least 10 characters.');
    }
  }
}
