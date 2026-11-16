import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class FriendInvite {
  const FriendInvite({
    required this.username,
    required this.signingPublicKey,
    required this.encryptionPublicKey,
    required this.encryptionKeySignature,
    required this.relayUrl,
  });

  final String username;
  final String signingPublicKey;
  final String encryptionPublicKey;
  final String encryptionKeySignature;
  final String relayUrl;

  String get id => '$username#${sha256.convert(base64Decode(signingPublicKey)).toString().substring(0, 4).toUpperCase()}';

  Map<String, Object?> toJson() => {
    'v': 1, 'username': username, 'signingPublicKey': signingPublicKey,
    'encryptionPublicKey': encryptionPublicKey,
    'encryptionKeySignature': encryptionKeySignature, 'relayUrl': relayUrl,
  };

  String toDeepLink() => 'vibechat://add?${Uri(queryParameters: toJson().map((k, v) => MapEntry(k, '$v'))).query}';

  static FriendInvite fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1 && json['v'] != '1') throw const FormatException('Unsupported Vibe invite version.');
    final invite = FriendInvite(
      username: json['username'] as String,
      signingPublicKey: json['signingPublicKey'] as String,
      encryptionPublicKey: json['encryptionPublicKey'] as String,
      encryptionKeySignature: json['encryptionKeySignature'] as String,
      relayUrl: json['relayUrl'] as String,
    );
    if (!RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(invite.username)) {
      throw const FormatException('Invalid username.');
    }
    final uri = Uri.tryParse(invite.relayUrl);
    if (uri == null || !['ws', 'wss'].contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('Invalid relay URL.');
    }
    return invite;
  }

  static FriendInvite parse(String input) {
    final value = input.trim();
    if (value.startsWith('{')) {\n      return fromJson(jsonDecode(value) as Map<String, dynamic>);\n    }\n    if (value.startsWith('vibechat://')) {
      final uri = Uri.parse(value);
      if (uri.scheme != 'vibechat' || uri.host != 'add') {
        throw const FormatException('This is not a Vibe Chat add link.');
      }
      return fromJson(uri.queryParameters);
    }
    throw const FormatException('A full QR code or vibechat:// link is required. An ID alone cannot verify public keys.');
  }

  Future<void> verify() async {
    final signingBytes = base64Decode(signingPublicKey);
    final encryptionBytes = base64Decode(encryptionPublicKey);
    final signatureBytes = base64Decode(encryptionKeySignature);
    if (signingBytes.length != 32 || encryptionBytes.length != 32 || signatureBytes.length != 64) {
      throw const FormatException('Invalid public key data.');
    }
    final expected = id.split('#').last;
    if (!RegExp(r'^[A-F0-9]{4}$').hasMatch(expected)) {
      throw const FormatException('Invalid Vibe ID fingerprint.');
    }
    final key = SimplePublicKey(signingBytes, type: KeyPairType.ed25519);
    final signature = Signature(signatureBytes, publicKey: key);
    final message = utf8.encode('vibe-chat-x25519-v1|$username|$encryptionPublicKey');
    if (!await Ed25519().verify(message, signature: signature)) {
      throw const FormatException('The encryption key signature is invalid.');
    }
  }

  factory FriendInvite.fromIdentity({
    required String username,
    required String signingPublicKey,
    required String encryptionPublicKey,
    required String encryptionKeySignature,
    required String relayUrl,
  }) => FriendInvite(username: username, signingPublicKey: signingPublicKey,
      encryptionPublicKey: encryptionPublicKey, encryptionKeySignature: encryptionKeySignature,
      relayUrl: relayUrl);
}
