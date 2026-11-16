import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_chat/models/chat_message.dart';
import 'package:vibe_chat/services/identity_service.dart';
import 'package:vibe_chat/services/mesh_message_crypto.dart';

Future<LocalIdentity> makeIdentity(String username) async {
  final signing = await Ed25519().newKeyPair();
  final encryption = await X25519().newKeyPair();
  final signingPublic = await signing.extractPublicKey();
  final encryptionPublic = await encryption.extractPublicKey();
  return LocalIdentity(
    username: username,
    publicKey: base64Encode(signingPublic.bytes),
    privateKey: base64Encode(await signing.extractPrivateKeyBytes()),
    userId: sha256.convert(signingPublic.bytes).toString(),
    encryptionPublicKey: base64Encode(encryptionPublic.bytes),
    encryptionPrivateKey: base64Encode(await encryption.extractPrivateKeyBytes()),
  );
}

void main() {
  test('mesh message is end-to-end encrypted and sender signature verifies', () async {
    final alice = await makeIdentity('alice');
    final bob = await makeIdentity('bob');
    final message = ChatMessage(
      id: 'message-123456789',
      conversationId: bob.displayId,
      senderId: alice.displayId,
      body: 'hello over mesh',
      moodId: 'neutral',
      soundId: 'neutral',
      createdAt: DateTime.utc(2026, 11, 16),
      isOutgoing: true,
    );
    final crypto = MeshMessageCrypto();
    final ciphertext = await crypto.encrypt(
      identity: alice,
      recipientEncryptionPublicKey: bob.encryptionPublicKey,
      message: message,
    );
    final clear = await crypto.decryptAndVerify(
      identity: bob,
      senderEncryptionPublicKey: alice.encryptionPublicKey,
      expectedSenderId: alice.displayId,
      expectedSigningPublicKey: alice.publicKey,
      ciphertext: ciphertext,
    );
    expect(clear['kind'], 'message');
    expect(clear['messageId'], message.id);
    expect(clear['text'], message.body);
    await expectLater(crypto.decryptAndVerify(
      identity: bob,
      senderEncryptionPublicKey: alice.encryptionPublicKey,
      expectedSenderId: alice.displayId,
      expectedSigningPublicKey: bob.publicKey,
      ciphertext: ciphertext,
    ), throwsA(isA<FormatException>()));
  });

  test('delivery receipt is encrypted and sender-authenticated', () async {
    final alice = await makeIdentity('alice');
    final bob = await makeIdentity('bob');
    final crypto = MeshMessageCrypto();
    final receipt = await crypto.encryptReceipt(
      identity: bob,
      recipientEncryptionPublicKey: alice.encryptionPublicKey,
      messageId: 'message-123456789',
    );
    final clear = await crypto.decryptAndVerify(
      identity: alice,
      senderEncryptionPublicKey: bob.encryptionPublicKey,
      expectedSenderId: bob.displayId,
      expectedSigningPublicKey: bob.publicKey,
      ciphertext: receipt,
    );
    expect(clear['kind'], 'receipt');
    expect(clear['messageId'], 'message-123456789');
  });
}
