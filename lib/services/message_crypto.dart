import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'identity_service.dart';

class MessageCrypto {
  static final _agreement = X25519();
  static final _cipher = Xchacha20.poly1305Aead();

  Future<String> encrypt({
    required LocalIdentity identity,
    required String recipientPublicKey,
    required Map<String, Object?> payload,
  }) async {
    final localPair = SimpleKeyPairData(
      base64Decode(identity.encryptionPrivateKey),
      publicKey: SimplePublicKey(base64Decode(identity.encryptionPublicKey), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final remote = SimplePublicKey(base64Decode(recipientPublicKey), type: KeyPairType.x25519);
    final shared = await _agreement.sharedSecretKey(keyPair: localPair, remotePublicKey: remote);
    final nonce = List<int>.generate(24, (_) => Random.secure().nextInt(256));
    final box = await _cipher.encrypt(utf8.encode(jsonEncode(payload)), secretKey: shared, nonce: nonce);
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Map<String, Object?>> decrypt({
    required LocalIdentity identity,
    required String senderPublicKey,
    required String ciphertext,
  }) async {
    final bytes = base64Decode(ciphertext);
    if (bytes.length < 40) throw const FormatException('Invalid encrypted envelope');
    final localPair = SimpleKeyPairData(
      base64Decode(identity.encryptionPrivateKey),
      publicKey: SimplePublicKey(base64Decode(identity.encryptionPublicKey), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final remote = SimplePublicKey(base64Decode(senderPublicKey), type: KeyPairType.x25519);
    final shared = await _agreement.sharedSecretKey(keyPair: localPair, remotePublicKey: remote);
    final clear = await _cipher.decrypt(
      SecretBox(bytes.sublist(24, bytes.length - 16),
          nonce: bytes.sublist(0, 24), mac: Mac(bytes.sublist(bytes.length - 16))),
      secretKey: shared,
    );
    final value = jsonDecode(utf8.decode(clear));
    if (value is! Map<String, dynamic>) throw const FormatException('Invalid message payload');
    return value;
  }
}
