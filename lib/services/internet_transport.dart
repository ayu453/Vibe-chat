import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/relay_config.dart';
import '../models/chat_message.dart';
import 'identity_service.dart';
import 'message_crypto.dart';
import 'message_transport.dart';

class InternetTransport implements MessageTransport {
  InternetTransport({required this.identity, required this.peerId, String relayUrl = RelayConfig.relayUrl})
      : _relayUrl = relayUrl { _connect(); }
  final LocalIdentity identity;
  final String peerId;
  final String _relayUrl;
  final _crypto = MessageCrypto();
  final _incoming = StreamController<ChatMessage>.broadcast();
  final _statuses = StreamController<MessageStatusUpdate>.broadcast();
  final _lookups = <String, Completer<Map<String, dynamic>?>>{};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _ready;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _attempt = 0;

  @override
  Stream<ChatMessage> get incomingMessages => _incoming.stream;
  @override
  Stream<MessageStatusUpdate> get statusUpdates => _statuses.stream;

  Future<void> _connect() async {
    if (_disposed || _channel != null) return;
    _ready = Completer<void>();
    try {
      final channel = WebSocketChannel.connect(Uri.parse(_relayUrl));
      _channel = channel;
      await channel.ready;
      _subscription = channel.stream.listen(_onPacket, onError: (_) => _scheduleReconnect(),
          onDone: _scheduleReconnect, cancelOnError: true);
    } catch (_) {
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _channel = null;
    _ready = null;
    _subscription?.cancel();
    _subscription = null;
    _attempt = min(_attempt + 1, 8);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: min(30, pow(2, _attempt).toInt())), _connect);
  }

  Future<SimpleKeyPairData> _signingPair() async => SimpleKeyPairData(
    base64Decode(identity.privateKey),
    publicKey: SimplePublicKey(base64Decode(identity.publicKey), type: KeyPairType.ed25519),
    type: KeyPairType.ed25519,
  );

  Future<void> _onPacket(dynamic raw) async {
    try {
      final packet = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (packet['type']) {
        case 'challenge':
          final proof = [
            ...base64Decode(packet['challenge'] as String),
            ...utf8.encode(identity.username),
            ...base64Decode(identity.encryptionPublicKey),
          ];
          final pair = await _signingPair();
          final signature = await Ed25519().sign(proof, keyPair: pair);
          final binding = utf8.encode('vibe-chat-x25519-v1|${identity.username}|${identity.encryptionPublicKey}');
          final keySignature = await Ed25519().sign(binding, keyPair: pair);
          _sendPacket({
            'type': 'auth', 'username': identity.username,
            'signingPublicKey': identity.publicKey,
            'encryptionPublicKey': identity.encryptionPublicKey,
            'signature': base64Encode(signature.bytes),
            'encryptionKeySignature': base64Encode(keySignature.bytes),
          });
          break;
        case 'authenticated':
          _attempt = 0;
          if (!(_ready?.isCompleted ?? true)) _ready!.complete();
          break;
        case 'lookup_result':
          final completer = _lookups.remove(packet['requestId']);
          if (completer != null && !completer.isCompleted) {
            completer.complete(packet['found'] == true ? packet : null);
          }
          break;
        case 'message':
          await _receive(packet);
          break;
        case 'status':
          _statuses.add(MessageStatusUpdate(packet['id'] as String, packet['status'] as String));
          break;
        case 'error':
          final id = packet['id'] as String?;
          if (id != null) _statuses.add(MessageStatusUpdate(id, 'failed'));
          break;
      }
    } catch (_) {}
  }

  Future<String> _verifyPeerKey(String expectedId, Map<String, dynamic> peer) async {
    final username = peer['username'] as String;
    final signingBytes = base64Decode(peer['signingPublicKey'] as String);
    final encryptionKey = peer['encryptionPublicKey'] as String;
    final signatureBytes = base64Decode(peer['encryptionKeySignature'] as String);
    final code = sha256.convert(signingBytes).toString().substring(0, 4).toUpperCase();
    if (expectedId != '$username#$code') throw const FormatException('Peer identity fingerprint mismatch');
    final publicKey = SimplePublicKey(signingBytes, type: KeyPairType.ed25519);
    final signature = Signature(signatureBytes, publicKey: publicKey);
    final binding = utf8.encode('vibe-chat-x25519-v1|$username|$encryptionKey');
    final valid = await Ed25519().verify(binding, signature: signature, publicKey: publicKey);
    if (!valid) throw const FormatException('Peer encryption key signature invalid');
    return encryptionKey;
  }

  Future<String?> _lookupPeer(String id) async {
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 20)}';
    final completer = Completer<Map<String, dynamic>?>();
    _lookups[requestId] = completer;
    _sendPacket({'type': 'lookup', 'to': id, 'requestId': requestId});
    final peer = await completer.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _lookups.remove(requestId);
      return null;
    });
    if (peer == null) return null;
    return _verifyPeerKey(id, peer);
  }

  Future<void> _receive(Map<String, dynamic> packet) async {
    final envelope = packet['envelope'] as Map<String, dynamic>;
    final sender = envelope['from'] as String;
    final senderKey = await _verifyPeerKey(sender, {
      'username': packet['senderUsername'],
      'signingPublicKey': packet['senderSigningPublicKey'],
      'encryptionPublicKey': packet['senderEncryptionPublicKey'],
      'encryptionKeySignature': packet['senderEncryptionKeySignature'],
    });
    final payload = await _crypto.decrypt(identity: identity, senderPublicKey: senderKey,
        ciphertext: envelope['ciphertext'] as String);
    _incoming.add(ChatMessage(
      id: envelope['id'] as String, conversationId: sender, senderId: sender,
      body: payload['text'] as String, moodId: payload['moodId'] as String,
      soundId: payload['soundId'] as String,
      createdAt: DateTime.tryParse(payload['createdAt'] as String? ?? '') ?? DateTime.now(),
      isOutgoing: false, status: 'delivered',
    ));
  }

  @override
  Future<void> send(ChatMessage message) async {
    await _ready?.future.timeout(const Duration(seconds: 12));
    if (_channel == null || _ready == null || !_ready!.isCompleted) throw StateError('Relay is not connected');
    final peerKey = await _lookupPeer(peerId);
    if (peerKey == null) throw StateError('Recipient has not registered with this relay yet');
    final ciphertext = await _crypto.encrypt(identity: identity, recipientPublicKey: peerKey, payload: {
      'text': message.body, 'moodId': message.moodId,
      'soundId': message.soundId, 'createdAt': message.createdAt.toIso8601String(),
    });
    _sendPacket({'type': 'message', 'envelope': {
      'id': message.id, 'to': peerId, 'from': identity.displayId,
      'ciphertext': ciphertext, 'ttl': 86400000,
    }});
  }

  void _sendPacket(Map<String, Object?> packet) {
    final channel = _channel;
    if (channel != null) channel.sink.add(jsonEncode(packet));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _incoming.close();
    await _statuses.close();
  }
}
