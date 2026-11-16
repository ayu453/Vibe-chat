import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'identity_service.dart';

/// Pairwise, directional daily tags. Direction prevents the sender from
/// subscribing to its own outgoing envelopes while keeping IDs off the wire.
class RouteTagService {
  const RouteTagService(this._pairwiseSecret);
  final List<int> _pairwiseSecret;
  static final X25519 _agreement = X25519();

  static Future<RouteTagService> forContact({
    required LocalIdentity identity,
    required String contactEncryptionPublicKey,
  }) async {
    final localPair = SimpleKeyPairData(
      base64Decode(identity.encryptionPrivateKey),
      publicKey: SimplePublicKey(
        base64Decode(identity.encryptionPublicKey), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final remote = SimplePublicKey(
      base64Decode(contactEncryptionPublicKey), type: KeyPairType.x25519);
    final shared = await _agreement.sharedSecretKey(
      keyPair: localPair, remotePublicKey: remote);
    return RouteTagService(await shared.extractBytes());
  }

  String tagForDay(
    DateTime day, {
    required String senderId,
    required String recipientId,
  }) {
    final utc = DateTime.utc(day.year, day.month, day.day);
    final dayLabel = '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
    final context = 'vibe-route-tag-v1|$senderId|$recipientId|$dayLabel';
    final mac = Hmac(sha256, _pairwiseSecret).convert(utf8.encode(context));
    return base64Url.encode(mac.bytes).replaceAll('=', '');
  }

  List<String> subscriptionTags(
    DateTime now, {
    required String senderId,
    required String recipientId,
  }) => [
    tagForDay(now, senderId: senderId, recipientId: recipientId),
    tagForDay(now.subtract(const Duration(days: 1)),
      senderId: senderId, recipientId: recipientId),
  ];
}
