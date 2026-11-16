import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Pairwise tags are derived from the X25519 shared secret. Never derive them
/// from a public key: that would let any observer calculate/track recipients.
class RouteTagService {
  const RouteTagService(this._pairwiseSecret);
  final List<int> _pairwiseSecret;

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
