import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../models/chat_message.dart';
import 'identity_service.dart';
import 'message_crypto.dart';

/// Adds sender authentication inside the encrypted payload. Carriers and relay
/// see neither the sender identity nor the message content.
class MeshMessageCrypto {
  final MessageCrypto _crypto = MessageCrypto();

  Future<String> encrypt({
    required LocalIdentity identity,
    required String recipientEncryptionPublicKey,
    required ChatMessage message,
  }) => _encryptPayload(identity, recipientEncryptionPublicKey, {
    'kind': 'message',
    'messageId': message.id,
    'text': message.body,
    'moodId': message.moodId,
    'soundId': message.soundId,
    'createdAt': message.createdAt.toIso8601String(),
  });

  Future<String> encryptReceipt({
    required LocalIdentity identity,
    required String recipientEncryptionPublicKey,
    required String messageId,
  }) => _encryptPayload(identity, recipientEncryptionPublicKey, {
    'kind': 'receipt',
    'messageId': messageId,
    'createdAt': DateTime.now().toIso8601String(),
  });

  Future<String> _encryptPayload(
    LocalIdentity identity,
    String recipientEncryptionPublicKey,
    Map<String, Object?> fields,
  ) async {
    final unsigned = <String, Object?>{
      'senderId': identity.displayId,
      'senderSigningPublicKey': identity.publicKey,
      ...fields,
    };
    final signingPair = SimpleKeyPairData(
      base64Decode(identity.privateKey),
      publicKey: SimplePublicKey(base64Decode(identity.publicKey), type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await Ed25519().sign(
      utf8.encode(jsonEncode(unsigned)), keyPair: signingPair);
    return _crypto.encrypt(
      identity: identity,
      recipientPublicKey: recipientEncryptionPublicKey,
      payload: {...unsigned, 'signature': base64Encode(signature.bytes)},
    );
  }

  Future<Map<String, Object?>> decryptAndVerify({
    required LocalIdentity identity,
    required String senderEncryptionPublicKey,
    required String expectedSenderId,
    required String expectedSigningPublicKey,
    required String ciphertext,
  }) async {
    final payload = await _crypto.decrypt(
      identity: identity,
      senderPublicKey: senderEncryptionPublicKey,
      ciphertext: ciphertext,
    );
    if (payload['senderId'] != expectedSenderId ||
        payload['senderSigningPublicKey'] != expectedSigningPublicKey) {
      throw const FormatException('Mesh sender identity mismatch');
    }
    final unsigned = Map<String, Object?>.from(payload)..remove('signature');
    final signatureBytes = base64Decode(payload['signature'] as String);
    final key = SimplePublicKey(base64Decode(expectedSigningPublicKey), type: KeyPairType.ed25519);
    final valid = await Ed25519().verify(
      utf8.encode(jsonEncode(unsigned)),
      signature: Signature(signatureBytes, publicKey: key),
    );
    if (!valid) throw const FormatException('Mesh sender signature invalid');
    return payload;
  }
}
