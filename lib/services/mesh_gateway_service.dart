import 'dart:async';
import '../models/chat_message.dart';
import '../models/mesh_envelope.dart';
import 'identity_service.dart';
import 'internet_transport.dart';
import 'local_database.dart';
import 'route_tag_service.dart';
import 'sqlite_mesh_outbox.dart';
import 'mesh_message_crypto.dart';

/// Subscribes only to pairwise tags for accepted contacts and verifies every
/// decrypted sender signature before inserting a chat message.
class MeshGatewayService {
  MeshGatewayService({
    required this.identity,
    required this.transport,
    LocalDatabase? database,
    SqliteMeshOutbox? outbox,
  }) : _db = database ?? LocalDatabase(),
       _outbox = outbox ?? SqliteMeshOutbox();

  final LocalIdentity identity;
  final InternetTransport transport;
  final LocalDatabase _db;
  final SqliteMeshOutbox _outbox;
  final MeshMessageCrypto _crypto = MeshMessageCrypto();
  StreamSubscription<MeshEnvelope>? _subscription;
  final Map<String, Map<String, Object?>> _contactsByTag = {};
  bool _disposed = false;

  Future<void> start() async {
    _subscription ??= transport.meshIncoming.listen(_receive);
    await refreshSubscriptions();
  }

  Future<void> refreshSubscriptions() async {
    if (_disposed) return;
    final contacts = await _db.contacts(status: 'accepted');
    final next = <String, Map<String, Object?>>{};
    for (final contact in contacts) {
      if ((contact['key_changed'] as int? ?? 0) == 1 ||
          contact['status'] == 'blocked') continue;
      final tags = await RouteTagService.forContact(
        identity: identity,
        contactEncryptionPublicKey: contact['encryption_public_key']! as String,
      ).then((service) => service.subscriptionTags(DateTime.now(), senderId: contact['id']! as String, recipientId: identity.displayId));
      for (final tag in tags) {
        next[tag] = contact;
      }
    }
    _contactsByTag
      ..clear()
      ..addAll(next);
    try {
      await transport.subscribeMeshTags(next.keys);
    } catch (_) {
      // The relay may still be reconnecting; the next refresh retries.
    }
  }

  Future<void> flushOutbox() async {
    if (_disposed) return;
    for (final envelope in await _outbox.all()) {
      try {
        await transport.publishMeshEnvelope(envelope);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _receive(MeshEnvelope envelope) async {
    final contact = _contactsByTag[envelope.tag];
    if (contact == null) return;
    final id = contact['id']! as String;
    if (contact['status'] != 'accepted' ||
        (contact['key_changed'] as int? ?? 0) == 1) return;
    try {
      await _outbox.store(envelope);
      final payload = await _crypto.decryptAndVerify(
        identity: identity,
        senderEncryptionPublicKey: contact['encryption_public_key']! as String,
        expectedSenderId: id,
        expectedSigningPublicKey: contact['signing_public_key']! as String,
        ciphertext: envelope.ciphertext,
      );
      if (payload['kind'] == 'receipt') {
        await _db.updateStatus(payload['messageId']! as String, 'delivered');
        await _outbox.remove(envelope.id);
        return;
      }
      if (payload['kind'] != 'message') {
        await _outbox.remove(envelope.id);
        return;
      }
      final message = ChatMessage(
        id: payload['messageId']! as String,
        conversationId: id,
        senderId: id,
        body: payload['text']! as String,
        moodId: payload['moodId']! as String,
        soundId: payload['soundId']! as String,
        createdAt: DateTime.tryParse(payload['createdAt']! as String) ?? DateTime.now(),
        isOutgoing: false,
        status: 'delivered',
      );
      await _db.insertMessage(message);
      final receiptCiphertext = await _crypto.encryptReceipt(
        identity: identity,
        recipientEncryptionPublicKey: contact['encryption_public_key']! as String,
        messageId: message.id,
      );
      final route = await RouteTagService.forContact(
        identity: identity,
        contactEncryptionPublicKey: contact['encryption_public_key']! as String,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final receipt = MeshEnvelope(
        id: 'receipt_${message.id}',
        tag: route.tagForDay(DateTime.now(),
          senderId: identity.displayId, recipientId: id),
        ciphertext: receiptCiphertext,
        createdAt: now,
        expiresAt: now + MeshEnvelope.maxLifetimeMs,
        hopCount: 0,
        copiesLeft: MeshEnvelope.maxCopies,
      );
      await _outbox.store(receipt, nowMs: now);
      try { await transport.publishMeshEnvelope(receipt); } catch (_) {}
      await _outbox.remove(envelope.id);
    } catch (_) {
      // Invalid packets are removed so they cannot occupy carrier storage.
      await _outbox.remove(envelope.id);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    await _outbox.close();
  }
}
