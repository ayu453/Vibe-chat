import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalIdentity {
  const LocalIdentity({
    required this.username,
    required this.publicKey,
    required this.privateKey,
    required this.userId,
  });

  final String username;
  final String publicKey;
  final String privateKey;
  final String userId;
  String get displayId => '$username#${userId.substring(0, 4).toUpperCase()}';
}

class IdentityService {
  static const _storage = FlutterSecureStorage();
  static const _usernameKey = 'vibe_username';
  static const _publicKeyKey = 'vibe_public_key';
  static const _privateKeyKey = 'vibe_private_key';

  Future<LocalIdentity> create(String username) async {
    final clean = username.trim();
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(clean)) {
      throw ArgumentError('Use 3–20 letters, numbers or underscores.');
    }
    final algorithm = Ed25519();
    final pair = await algorithm.newKeyPair();
    final public = await pair.extractPublicKey();
    final privateBytes = await pair.extractPrivateKeyBytes();
    final publicEncoded = base64Encode(public.bytes);
    final privateEncoded = base64Encode(privateBytes);
    final code = sha256.convert(public.bytes).toString();
    await _storage.write(key: _usernameKey, value: clean);
    await _storage.write(key: _publicKeyKey, value: publicEncoded);
    await _storage.write(key: _privateKeyKey, value: privateEncoded);
    return LocalIdentity(
      username: clean,
      publicKey: publicEncoded,
      privateKey: privateEncoded,
      userId: code,
    );
  }

  Future<LocalIdentity?> load() async {
    final username = await _storage.read(key: _usernameKey);
    final publicKey = await _storage.read(key: _publicKeyKey);
    final privateKey = await _storage.read(key: _privateKeyKey);
    if (username == null || publicKey == null || privateKey == null) return null;
    final bytes = base64Decode(publicKey);
    return LocalIdentity(
      username: username,
      publicKey: publicKey,
      privateKey: privateKey,
      userId: sha256.convert(bytes).toString(),
    );
  }
}
