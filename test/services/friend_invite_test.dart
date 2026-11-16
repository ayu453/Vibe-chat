import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:vibe_chat/services/friend_invite.dart';

void main() {
  test('Vibe ID fingerprint is derived from Ed25519 public key and verifies key binding', () async {
    final pair = await Ed25519().newKeyPair();
    final pub = await pair.extractPublicKey();
    final x = await X25519().newKeyPair();
    final xPub = base64Encode((await x.extractPublicKey()).bytes);
    final binding = utf8.encode('vibe-chat-x25519-v1|reader|$xPub');
    final sig = await Ed25519().sign(binding, keyPair: pair);
    final invite = FriendInvite.fromIdentity(username: 'reader',
      signingPublicKey: base64Encode(pub.bytes), encryptionPublicKey: xPub,
      encryptionKeySignature: base64Encode(sig.bytes), relayUrl: 'wss://relay.example');
    await invite.verify();
    expect(invite.id, startsWith('reader#'));
    final tampered = FriendInvite.fromIdentity(username: 'reader',
      signingPublicKey: invite.signingPublicKey, encryptionPublicKey: base64Encode(List<int>.filled(32, 9)),
      encryptionKeySignature: invite.encryptionKeySignature, relayUrl: invite.relayUrl);
    expect(tampered.verify, throwsA(isA<FormatException>()));
  });

  test('plain ID cannot be accepted as a verified invite', () {
    expect(() => FriendInvite.parse('reader#AB12'), throwsFormatException);
  });
}
