import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_chat/models/mesh_envelope.dart';
import 'package:vibe_chat/services/mesh_simulator.dart';
import 'package:vibe_chat/services/mesh_store.dart';
import 'package:vibe_chat/services/route_tag_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:vibe_chat/services/identity_service.dart';

void main() {
  const now = 1800000000000;
  MeshEnvelope packet() => const MeshEnvelope(
    id: 'envelope_identifier_0001',
    tag: 'recipient_route_tag_01',
    ciphertext: 'opaque-ciphertext',
    createdAt: now - 1000,
    expiresAt: now + 3600000,
    hopCount: 0,
    copiesLeft: 6,
  );

  test('five-node chain carries opaque envelope to internet gateway', () {
    final result = MeshSimulator().run(envelope: packet(), nowMs: now);
    expect(result.path, ['A', 'B', 'C', 'D', 'E']);
    expect(result.reachedGateway, isTrue);
    expect(result.reachedRelay, isTrue);
    expect(result.reachedRecipient, isTrue);
    expect(result.uploadedIds, [packet().id]);
  });

  test('forwarding splits copy budget without increasing total copies', () {
    final split = packet().splitForForward();
    expect(split.transferred.copiesLeft + split.remainingAtSender.copiesLeft,
        packet().copiesLeft);
    expect(split.transferred.hopCount, 1);
    expect(split.remainingAtSender.hopCount, 0);
  });

  test('store deduplicates and evicts oldest first under byte limit', () {
    final store = MeshStore(maxBytes: 350);
    expect(store.store(packet(), nowMs: now), isTrue);
    expect(store.store(packet(), nowMs: now), isFalse);
    final newer = MeshEnvelope(
      id: 'envelope_identifier_0002', tag: packet().tag,
      ciphertext: List.filled(80, 'x').join(), createdAt: now, expiresAt: now + 100000,
      hopCount: 0, copiesLeft: 1);
    store.store(newer, nowMs: now);
    expect(store.contains(newer.id), isTrue);
    expect(store.contains(packet().id), isFalse);
  });

  test('expired packets are rejected', () {
    final expired = MeshEnvelope(
      id: 'expired_envelope_identifier', tag: packet().tag,
      ciphertext: 'opaque', createdAt: now - 10000,
      expiresAt: now - 1, hopCount: 0, copiesLeft: 1);
    expect(() => MeshStore().store(expired, nowMs: now), throwsFormatException);
  });

  test('route tags rotate daily and include yesterday during overlap', () {
    const tags = RouteTagService([1, 2, 3, 4, 5, 6]);
    final day = DateTime.utc(2026, 11, 16);
    expect(tags.tagForDay(day, senderId: 'alice', recipientId: 'bob'), isNot(tags.tagForDay(day.add(const Duration(days: 1)), senderId: 'alice', recipientId: 'bob')));
    expect(tags.subscriptionTags(day, senderId: 'alice', recipientId: 'bob'), [tags.tagForDay(day, senderId: 'alice', recipientId: 'bob'), tags.tagForDay(day.subtract(const Duration(days: 1)), senderId: 'alice', recipientId: 'bob')]);
  });

  test('X25519 contact pair derives matching route tags', () async {
    final algorithm = X25519();
    final alicePair = await algorithm.newKeyPair();
    final bobPair = await algorithm.newKeyPair();
    final alicePublic = await alicePair.extractPublicKey();
    final bobPublic = await bobPair.extractPublicKey();
    final alice = LocalIdentity(
      username: 'alice', publicKey: 'sign', privateKey: 'private',
      userId: 'alice-id', encryptionPublicKey: base64Encode(alicePublic.bytes),
      encryptionPrivateKey: base64Encode(await alicePair.extractPrivateKeyBytes()));
    final bob = LocalIdentity(
      username: 'bob', publicKey: 'sign2', privateKey: 'private2',
      userId: 'bob-id', encryptionPublicKey: base64Encode(bobPublic.bytes),
      encryptionPrivateKey: base64Encode(await bobPair.extractPrivateKeyBytes()));
    final a = await RouteTagService.forContact(
      identity: alice, contactEncryptionPublicKey: bob.encryptionPublicKey);
    final b = await RouteTagService.forContact(
      identity: bob, contactEncryptionPublicKey: alice.encryptionPublicKey);
    final day = DateTime.utc(2026, 11, 16);
    expect(a.tagForDay(day, senderId: 'alice', recipientId: 'bob'), b.tagForDay(day, senderId: 'alice', recipientId: 'bob'));
    expect(a.tagForDay(day, senderId: 'alice', recipientId: 'bob'), isNot(a.tagForDay(day, senderId: 'bob', recipientId: 'alice')));
  });

  test('same shared secret yields same tag; different contact secret does not', () {
    final a = RouteTagService(List<int>.filled(32, 7));
    final b = RouteTagService(List<int>.filled(32, 7));
    final other = RouteTagService(List<int>.filled(32, 8));
    final day = DateTime.utc(2026, 11, 16);
    expect(a.tagForDay(day, senderId: 'alice', recipientId: 'bob'), b.tagForDay(day, senderId: 'alice', recipientId: 'bob'));
    expect(a.tagForDay(day, senderId: 'alice', recipientId: 'bob'), isNot(other.tagForDay(day, senderId: 'alice', recipientId: 'bob')));
  });
}
