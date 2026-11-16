import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalIdentity {
  const LocalIdentity({
    required this.username, required this.publicKey, required this.privateKey,
    required this.userId, required this.encryptionPublicKey, required this.encryptionPrivateKey,
  });
  final String username;
  final String publicKey;
  final String privateKey;
  final String userId;
  final String encryptionPublicKey;
  final String encryptionPrivateKey;
  String get displayId => '$username#${userId.substring(0, 4).toUpperCase()}';
}

class IdentityService {
  static const _storage = FlutterSecureStorage();
  static const _usernameKey = 'vibe_username';
  static const _publicKeyKey = 'vibe_public_key';
  static const _privateKeyKey = 'vibe_private_key';
  static const _encPublicKey = 'vibe_x25519_public_key';
  static const _encPrivateKey = 'vibe_x25519_private_key';

  Future<LocalIdentity> create(String username) async {
    final clean = username.trim();
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(clean)) {
      throw ArgumentError('Use 3–20 letters, numbers or underscores.');
    }
    final signing = await Ed25519().newKeyPair();
    final signingPublic = await signing.extractPublicKey();
    final signingPrivate = await signing.extractPrivateKeyBytes();
    final encryption = await X25519().newKeyPair();
    final encryptionPublic = await encryption.extractPublicKey();
    final encryptionPrivate = await encryption.extractPrivateKeyBytes();
    final publicEncoded = base64Encode(signingPublic.bytes);
    final privateEncoded = base64Encode(signingPrivate);
    final encPublicEncoded = base64Encode(encryptionPublic.bytes);
    final encPrivateEncoded = base64Encode(encryptionPrivate);
    await _storage.write(key: _usernameKey, value: clean);
    await _storage.write(key: _publicKeyKey, value: publicEncoded);
    await _storage.write(key: _privateKeyKey, value: privateEncoded);
    await _storage.write(key: _encPublicKey, value: encPublicEncoded);
    await _storage.write(key: _encPrivateKey, value: encPrivateEncoded);
    return LocalIdentity(
      username: clean, publicKey: publicEncoded, privateKey: privateEncoded,
      userId: sha256.convert(signingPublic.bytes).toString(),
      encryptionPublicKey: encPublicEncoded, encryptionPrivateKey: encPrivateEncoded,
    );
  }

  Future<LocalIdentity?> load() async {
    final username = await _storage.read(key: _usernameKey);
    final publicKey = await _storage.read(key: _publicKeyKey);
    final privateKey = await _storage.read(key: _privateKeyKey);
    if (username == null || publicKey == null || privateKey == null) return null;
    var encPublic = await _storage.read(key: _encPublicKey);
    var encPrivate = await _storage.read(key: _encPrivateKey);
    if (encPublic == null || encPrivate == null) {
      final pair = await X25519().newKeyPair();
      encPublic = base64Encode((await pair.extractPublicKey()).bytes);
      encPrivate = base64Encode(await pair.extractPrivateKeyBytes());
      await _storage.write(key: _encPublicKey, value: encPublic);
      await _storage.write(key: _encPrivateKey, value: encPrivate);
    }
    return LocalIdentity(
      username: username, publicKey: publicKey, privateKey: privateKey,
      userId: sha256.convert(base64Decode(publicKey)).toString(),
      encryptionPublicKey: encPublic, encryptionPrivateKey: encPrivate,
    );
  }
}
