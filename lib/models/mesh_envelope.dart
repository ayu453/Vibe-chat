import 'dart:convert';

/// Opaque packet carried by relays. No sender or recipient identity is exposed.
class MeshEnvelope {
  const MeshEnvelope({
    required this.id,
    required this.tag,
    required this.ciphertext,
    required this.createdAt,
    required this.expiresAt,
    required this.hopCount,
    required this.copiesLeft,
  });

  static const int maxBytes = 32 * 1024;
  static const int maxLifetimeMs = 48 * 60 * 60 * 1000;
  static const int maxHops = 8;
  static const int maxCopies = 6;

  final String id;
  final String tag;
  final String ciphertext;
  final int createdAt;
  final int expiresAt;
  final int hopCount;
  final int copiesLeft;

  bool isExpiredAt(int nowMs) => expiresAt <= nowMs;
  bool get canForward => hopCount < maxHops && copiesLeft > 0;

  Map<String, Object> toJson() => {
    'id': id,
    'tag': tag,
    'ciphertext': ciphertext,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'hopCount': hopCount,
    'copiesLeft': copiesLeft,
  };

  String encode() => jsonEncode(toJson());

  factory MeshEnvelope.fromJson(Map<String, dynamic> json) {
    final envelope = MeshEnvelope(
      id: json['id'] as String,
      tag: json['tag'] as String,
      ciphertext: json['ciphertext'] as String,
      createdAt: json['createdAt'] as int,
      expiresAt: json['expiresAt'] as int,
      hopCount: json['hopCount'] as int,
      copiesLeft: json['copiesLeft'] as int,
    );
    envelope.validate();
    return envelope;
  }

  void validate({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (!RegExp(r'^[A-Za-z0-9_-]{16,96}$').hasMatch(id)) {
      throw const FormatException('Invalid envelope id');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{16,96}$').hasMatch(tag)) {
      throw const FormatException('Invalid route tag');
    }
    if (ciphertext.isEmpty || utf8.encode(encode()).length > maxBytes) {
      throw const FormatException('Envelope exceeds size limit');
    }
    if (createdAt > now + 5 * 60 * 1000 || expiresAt <= createdAt ||
        expiresAt - createdAt > maxLifetimeMs) {
      throw const FormatException('Invalid envelope lifetime');
    }
    if (hopCount < 0 || hopCount > maxHops ||
        copiesLeft < 0 || copiesLeft > maxCopies) {
      throw const FormatException('Invalid forwarding budget');
    }
  }

  MeshEnvelope forwarded() {
    if (!canForward) throw StateError('Forwarding budget exhausted');
    return MeshEnvelope(
      id: id,
      tag: tag,
      ciphertext: ciphertext,
      createdAt: createdAt,
      expiresAt: expiresAt,
      hopCount: hopCount + 1,
      copiesLeft: copiesLeft - 1,
    );
  }
}
