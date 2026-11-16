import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:vibe_chat/services/identity_service.dart';
import 'package:vibe_chat/services/message_crypto.dart';

void main() {
  test('X25519 and XChaCha20-Poly1305 encrypt and decrypt mood payload', () async {
    final alicePair = await X25519().newKeyPair();
    final bobPair = await X25519().newKeyPair();
    final alicePublic = await alicePair.extractPublicKey();
    final bobPublic = await bobPair.extractPublicKey();
    final alicePrivate = await alicePair.extractPrivateKeyBytes();
    final bobPrivate = await bobPair.extractPrivateKeyBytes();
    final alice = LocalIdentity(
      username: 'alice', publicKey: '', privateKey: '', userId: 'a',
      encryptionPublicKey: base64Encode(alicePublic.bytes),
      encryptionPrivateKey: base64Encode(alicePrivate),
    );
    final bob = LocalIdentity(
      username: 'bob', publicKey: '', privateKey: '', userId: 'b',
      encryptionPublicKey: base64Encode(bobPublic.bytes),
      encryptionPrivateKey: base64Encode(bobPrivate),
    );
    final crypto = MessageCrypto();
    final encrypted = await crypto.encrypt(
      identity: alice,
      recipientPublicKey: bob.encryptionPublicKey,
      payload: {'text': 'hello', 'moodId': 'love', 'soundId': 'love'},
    );
    final clear = await crypto.decrypt(
      identity: bob,
      senderPublicKey: alice.encryptionPublicKey,
      ciphertext: encrypted,
    );
    expect(clear['text'], 'hello');
    expect(clear['moodId'], 'love');
    expect(clear['soundId'], 'love');
  });
}
