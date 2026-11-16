import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'identity_service.dart';

/// Pairwise tags are derived from the X25519 shared secret. Never derive them
/// from a public key: that would let any observer calculate/track recipients.
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

  String tagForDay(DateTime day) {
    final utc = DateTime.utc(day.year, day.month, day.day);
    final dayLabel = '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
    final mac = Hmac(sha256, _pairwiseSecret)
        .convert(utf8.encode('vibe-route-tag-v1|$dayLabel'));
    return base64Url.encode(mac.bytes).replaceAll('=', '');
  }

  /// Current day plus previous day allows messages crossing midnight.
  List<String> subscriptionTags(DateTime now) => [
    tagForDay(now),
    tagForDay(now.subtract(const Duration(days: 1))),
  ];
}
