import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/relay_config.dart';
import '../legacy_main.dart' show ChatScreen, SettingsScreen;
import '../models/chat_message.dart';
import '../services/friend_invite.dart';
import '../services/identity_service.dart';
import '../services/internet_transport.dart';
import '../services/local_database.dart';
import '../services/friend_request_policy.dart';
import 'mesh_debug_screen.dart';
import '../services/mesh_gateway_service.dart';
import '../services/nearby_mesh_transport.dart';

class FriendHomeScreen extends StatefulWidget {
  const FriendHomeScreen({super.key, required this.identity});
  final LocalIdentity identity;
  @override
  State<FriendHomeScreen> createState() => _FriendHomeScreenState();
}

class _FriendHomeScreenState extends State<FriendHomeScreen> with SingleTickerProviderStateMixin {
  final _db = LocalDatabase();
  late final InternetTransport _transport;
  late final MeshGatewayService _meshGateway;
  late final NearbyMeshTransport _nearbyMesh;
  late final TabController _tabs;
  StreamSubscription<ChatMessage>? _incoming;
  StreamSubscription<Uri>? _links;
  Timer? _refreshTimer;
  List<Map<String, Object?>> _accepted = [];
  List<Map<String, Object?>> _requests = [];
  List<Map<String, Object?>> _recent = [];
  FriendInvite? _myInvite;
  late final Future<void> _inviteReady;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _transport = InternetTransport(identity: widget.identity);
    _nearbyMesh = NearbyMeshTransport();
    _meshGateway = MeshGatewayService(identity: widget.identity, transport: _transport);
    unawaited(_meshGateway.start());
    _incoming = _transport.incomingMessages.listen(_handleIncoming);
    _inviteReady = _loadMyInvite();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
    _initLinks();
  }

  Future<void> _loadMyInvite() async {
    final binding = utf8.encode('vibe-chat-x25519-v1|${widget.identity.username}|${widget.identity.encryptionPublicKey}');
    final pair = SimpleKeyPairData(
      base64Decode(widget.identity.privateKey),
      publicKey: SimplePublicKey(base64Decode(widget.identity.publicKey), type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await Ed25519().sign(binding, keyPair: pair);
    if (!mounted) return;
    setState(() => _myInvite = FriendInvite.fromIdentity(
      username: widget.identity.username, signingPublicKey: widget.identity.publicKey,
      encryptionPublicKey: widget.identity.encryptionPublicKey,
      encryptionKeySignature: base64Encode(signature.bytes), relayUrl: RelayConfig.relayUrl,
    ));
  }

  Future<void> _initLinks() async {
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null && mounted) _openInviteText(initial.toString());
    } catch (_) {}
    _links = links.uriLinkStream.listen((uri) {
      if (mounted) _openInviteText(uri.toString());
    });
  }

  Future<void> _refresh() async {
    final accepted = await _db.contacts(status: 'accepted');
    final requests = await _db.contacts(status: 'requested');
    final recent = await _db.conversations();
    if (!mounted) return;
    setState(() { _accepted = accepted; _requests = requests; _recent = recent; _loading = false; });
  }

  bool _isControl(String body) => body.startsWith('vibe-control:');

  Future<void> _handleIncoming(ChatMessage message) async {
    if (await _db.isBlocked(message.conversationId)) return;
    if (_isControl(message.body)) {
      try {
        final data = jsonDecode(message.body.substring('vibe-control:'.length)) as Map<String, dynamic>;
        final invite = FriendInvite.fromJson(data['invite'] as Map<String, dynamic>);
        await invite.verify();
        if (invite.id != message.conversationId) return;
        final old = await _db.contact(invite.id);
        if (old != null && (old['signing_public_key'] != invite.signingPublicKey ||
            old['encryption_public_key'] != invite.encryptionPublicKey)) {
          await _db.markContactKeyChanged(invite.id, signingPublicKey: invite.signingPublicKey,
            encryptionPublicKey: invite.encryptionPublicKey, encryptionKeySignature: invite.encryptionKeySignature);
          unawaited(_meshGateway.refreshSubscriptions());
        } else if (data['action'] == 'request') {
          final existingContacts = await _db.contacts();
          final nameCollision = existingContacts.any((item) =>
              item['username'] == invite.username && item['id'] != invite.id);
          if (nameCollision && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Warning: same username received with a different Vibe ID.')));
          }
          await _db.saveContact(id: invite.id, username: invite.username,
            signingPublicKey: invite.signingPublicKey, encryptionPublicKey: invite.encryptionPublicKey,
            encryptionKeySignature: invite.encryptionKeySignature, relayUrl: invite.relayUrl,
            status: 'requested', direction: 'incoming');
        } else if (data['action'] == 'accepted') {
          await _db.setContactStatus(invite.id, 'accepted');
          unawaited(_meshGateway.refreshSubscriptions());
        }
      } catch (_) {}
      await _refresh();
      return;
    }
    final contact = await _db.contact(message.conversationId);
    if (contact == null || contact['status'] != 'accepted' || (contact['key_changed'] as int? ?? 0) == 1) return;
    await _db.insertMessage(message);
    await _refresh();
  }

  Future<void> _sendControl(String id, String action) async {
    await _inviteReady;
    final me = _myInvite;
    if (me == null) throw StateError('Your identity card is still loading.');
    final control = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      conversationId: id, senderId: widget.identity.userId,
      body: 'vibe-control:${jsonEncode({'action': action, 'invite': me.toJson()})}',
      moodId: 'neutral', soundId: 'neutral', createdAt: DateTime.now(),
      isOutgoing: true, status: 'sending',
    );
    await _transport.send(control);
  }

  Future<void> _openInviteText(String text) async {
    try {
      final trimmed = text.trim();
      final idMatch = RegExp(r'^[A-Za-z0-9_]{3,20}#[A-Fa-f0-9]{4}$').firstMatch(trimmed);
      final normalizedId = trimmed.replaceFirstMapped(
        RegExp(r'#[a-fA-F0-9]{4}$'), (match) => match[0]!.toUpperCase());
      final invite = idMatch != null
          ? await _transport.resolveInvite(normalizedId)
          : FriendInvite.parse(trimmed);
      if (invite == null) {
        throw const FormatException('That Vibe ID is not known to this relay yet. Ask them to open Vibe Chat once, or use their QR/link.');
      }
      await _confirmInvite(invite);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('FormatException: ', ''))));
      }
    }
  }

  Future<void> _confirmInvite(FriendInvite invite) async {
    await invite.verify();
    if (invite.relayUrl != RelayConfig.relayUrl) {
      throw const FormatException('This invite uses a different relay. Switch your relay setting before adding this friend.');
    }
    if (!mounted) return;
    final allContacts = await _db.contacts();
    final sameName = allContacts.any((c) => c['username'] == invite.username && c['id'] != invite.id);
    final result = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Confirm friend'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(invite.username, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4), SelectableText(invite.id),
        if (sameName) const Padding(padding: EdgeInsets.only(top: 10),
          child: Text('Warning: another contact uses this username with a different code.', style: TextStyle(color: Colors.deepOrange))),
        const SizedBox(height: 10), const Text('This sends a request. Chat opens only after they accept.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send request')),
      ],
    ));
    if (result != true) return;
    final old = await _db.contact(invite.id);
    if (old != null && (old['signing_public_key'] != invite.signingPublicKey ||
        old['encryption_public_key'] != invite.encryptionPublicKey)) {
      await _db.markContactKeyChanged(invite.id, signingPublicKey: invite.signingPublicKey,
        encryptionPublicKey: invite.encryptionPublicKey, encryptionKeySignature: invite.encryptionKeySignature);
      unawaited(_meshGateway.refreshSubscriptions());
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Key changed. Confirm it before messaging.')));
      return;
    }
    await _db.saveContact(id: invite.id, username: invite.username,
      signingPublicKey: invite.signingPublicKey, encryptionPublicKey: invite.encryptionPublicKey,
      encryptionKeySignature: invite.encryptionKeySignature, relayUrl: invite.relayUrl,
      status: 'requested', direction: 'outgoing');
    try { await _sendControl(invite.id, 'request'); } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request saved locally; delivery failed: $e')));
    }
    await _refresh();
  }

  Future<void> _accept(Map<String, Object?> contact) async {
    if (!FriendRequestPolicy.canAccept(status: contact['status']! as String, direction: contact['direction']! as String)) return;
    final id = contact['id']! as String;
    await _db.setContactStatus(id, 'accepted');
    unawaited(_meshGateway.refreshSubscriptions());
    try { await _sendControl(id, 'accepted'); } catch (_) {}
    await _refresh();
  }

  Future<void> _block(String id) async {
    await _db.setContactStatus(id, 'blocked');
    unawaited(_meshGateway.refreshSubscriptions());
    await _refresh();
  }

  Future<void> _confirmChangedKey(Map<String, Object?> contact) async {
    final id = contact['id']! as String;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Confirm public key change'),
      content: Text('The encryption key for $id changed. Only continue if you verified this change with the person through another trusted channel.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm key'))],
    ));
    if (confirmed == true) { await _db.confirmContactKey(id); unawaited(_meshGateway.refreshSubscriptions()); await _refresh(); }
  }

  Future<void> _delete(String id) async {
    await _db.deleteContact(id);
    unawaited(_meshGateway.refreshSubscriptions());
    await _refresh();
  }

  void _openChat(Map<String, Object?> contact) {
    if (!FriendRequestPolicy.canOpenChat(status: contact['status']! as String,
        keyChanged: (contact['key_changed'] as int? ?? 0) == 1)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirm the changed key before opening this chat.')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
      identity: widget.identity, transport: _transport,
      conversationId: contact['id']! as String, contactName: contact['username']! as String,
    ))).then((_) => _refresh());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _incoming?.cancel();
    _links?.cancel();
    _refreshTimer?.cancel();
    _meshGateway.dispose();
    _nearbyMesh.dispose();
    _transport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Vibe Chat', style: TextStyle(fontWeight: FontWeight.bold)),
      actions: [
        IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        IconButton(tooltip: 'Mesh debug', icon: const Icon(Icons.hub_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MeshDebugScreen(transport: _nearbyMesh)))),
        IconButton(tooltip: 'My ID card', icon: const Icon(Icons.qr_code_2),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyIdCardScreen(identity: widget.identity, invite: _myInvite)))),
        IconButton(tooltip: 'Add friend', icon: const Icon(Icons.person_add_alt_1), onPressed: _addFriend),
      ],
      bottom: TabBar(controller: _tabs, tabs: [
        Tab(text: 'Chats (${_accepted.length})'), Tab(text: 'Requests (${_requests.length})'),
      ]),
    ),
    body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabs, children: [
      _accepted.isEmpty ? const Center(child: Text('No accepted friends yet. Add someone by QR or ID.')) :
        ListView(children: _accepted.map((c) {
          final last = _recent.where((m) => m['conversation_id'] == c['id']).toList();
          final changed = (c['key_changed'] as int? ?? 0) == 1;
          return ListTile(
            leading: CircleAvatar(child: Text((c['username']! as String)[0].toUpperCase())),
            title: Text(c['username']! as String),
            subtitle: Text(changed ? 'Public key changed — confirmation required' :
              last.isEmpty ? c['id']! as String : last.first['body']! as String, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: changed ? null : () => _openChat(c),
            trailing: changed
              ? IconButton(tooltip: 'Confirm changed key', icon: const Icon(Icons.verified_user_outlined), onPressed: () => _confirmChangedKey(c))
              : PopupMenuButton<String>(onSelected: (v) => v == 'block' ? _block(c['id']! as String) : _delete(c['id']! as String),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'block', child: Text('Block')), PopupMenuItem(value: 'delete', child: Text('Delete contact'))]),
          );
        }).toList()),
      _requests.isEmpty ? const Center(child: Text('No friend requests.')) :
        ListView(children: _requests.map((c) => ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(c['username']! as String),
          subtitle: Text('${c['id']} • ${c['direction']}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if ((c['key_changed'] as int? ?? 0) == 1)
              IconButton(tooltip: 'Confirm changed key', icon: const Icon(Icons.verified_user_outlined), onPressed: () => _confirmChangedKey(c))
            else if (c['direction'] == 'incoming')
              FilledButton(onPressed: () => _accept(c), child: const Text('Accept'))
            else
              const Text('Pending'),
            PopupMenuButton<String>(onSelected: (v) => v == 'block'
                ? _block(c['id']! as String) : _delete(c['id']! as String),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'block', child: Text('Block')),
                PopupMenuItem(value: 'delete', child: Text('Delete contact')),
              ]),
          ]),
        )).toList()),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _addFriend,
      icon: const Icon(Icons.person_add_alt_1), label: const Text('Add friend')),
  );

  Future<void> _addFriend() async {
    final text = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const AddFriendScreen()));
    if (text != null && text.isNotEmpty) await _openInviteText(text);
  }
}

class MyIdCardScreen extends StatelessWidget {
  const MyIdCardScreen({super.key, required this.identity, required this.invite});
  final LocalIdentity identity;
  final FriendInvite? invite;
  @override
  Widget build(BuildContext context) {
    final qr = invite == null ? '' : jsonEncode(invite!.toJson());
    final link = invite?.toDeepLink() ?? '';
    return Scaffold(appBar: AppBar(title: const Text('My Vibe ID')),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
        Text(identity.displayId, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        if (qr.isNotEmpty) QrImageView(data: qr, size: 250, backgroundColor: Colors.white),
        const SizedBox(height: 16),
        const Text('Scan this QR to add me. Your phone number is never needed.'),
        const SizedBox(height: 20),
        OutlinedButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: identity.displayId)),
          icon: const Icon(Icons.copy), label: const Text('Copy ID')),
        FilledButton.icon(onPressed: link.isEmpty ? null : () => Share.share(link),
          icon: const Icon(Icons.share), label: const Text('Share link')),
      ]))));
  }
}

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});
  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}
class _AddFriendScreenState extends State<AddFriendScreen> {
  final _controller = TextEditingController();
  bool _scanning = false;
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add a friend')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      OutlinedButton.icon(onPressed: () => setState(() => _scanning = !_scanning),
        icon: const Icon(Icons.qr_code_scanner), label: Text(_scanning ? 'Close scanner' : 'Scan QR code')),
      if (_scanning) SizedBox(height: 300, child: ClipRRect(borderRadius: BorderRadius.circular(16),
        child: MobileScanner(onDetect: (capture) {
          final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
          if (raw != null && mounted) Navigator.pop(context, raw);
        }))),
      const SizedBox(height: 20),
      TextField(controller: _controller, minLines: 1, maxLines: 3,
        decoration: const InputDecoration(labelText: 'Paste vibechat:// link or Vibe ID', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Continue')),
      const SizedBox(height: 8),
      const Text('For a Vibe ID, the app resolves its public keys through your configured relay and verifies the fingerprint before adding.', style: TextStyle(color: Colors.black54)),
    ]),
  );
}
