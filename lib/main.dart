import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/chat_message.dart';
import 'services/identity_service.dart';
import 'services/internet_transport.dart';
import 'services/local_database.dart';
import 'services/message_transport.dart';
import 'services/mood_detector.dart';
import 'services/mood_media_service.dart';

void main() => runApp(const VibeChatApp());

class VibeChatApp extends StatelessWidget {
  const VibeChatApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Vibe Chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6558D3),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F6FC),
        ),
        home: const AppGate(),
      );
}

class AppGate extends StatefulWidget {
  const AppGate({super.key});
  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  final _identity = IdentityService();
  LocalIdentity? _current;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _identity.load().then((value) {
      if (!mounted) return;
      setState(() {
        _current = value;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_current == null) {
      return OnboardingScreen(onCreated: (identity) {
        setState(() => _current = identity);
      });
    }
    return ChatListScreen(identity: _current!);
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onCreated});
  final ValueChanged<LocalIdentity> onCreated;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final identity = await IdentityService().create(_controller.text);
      widget.onCreated(identity);
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('ArgumentError: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.forum_rounded, size: 66, color: Color(0xFF6558D3)),
                  const SizedBox(height: 20),
                  Text('Your vibe. Your identity.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text('Choose a username to create your private Vibe ID.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'e.g. moonwalker',
                      prefixText: '@',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _create,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Create my Vibe ID'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Your keypair is generated on this device. Your identity stays local.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ),
        ),
      );
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.identity});
  final LocalIdentity identity;
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _db = LocalDatabase();
  List<Map<String, Object?>> _recent = [];
  final _contacts = <String, String>{};
  late final InternetTransport _transport;
  StreamSubscription<ChatMessage>? _incomingSubscription;
  StreamSubscription<MessageStatusUpdate>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _transport = InternetTransport(identity: widget.identity);
    _incomingSubscription = _transport.incomingMessages.listen((message) async {
      await _db.insertMessage(message);
      await _refresh();
    });
    _statusSubscription = _transport.statusUpdates.listen((update) {
      _db.updateStatus(update.messageId, update.status);
    });
    _refresh();
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    _statusSubscription?.cancel();
    _transport.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final rows = await _db.conversations();
    if (mounted) setState(() => _recent = rows);
  }

  Future<void> _addContact() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Vibe ID (username#XXXX)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    final match = RegExp(r'^([A-Za-z0-9_]{3,20})#([A-Fa-f0-9]{4})$').firstMatch(value);
    if (match == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a Vibe ID in username#XXXX format.')),
        );
      }
      return;
    }
    final id = '${match.group(1)}#${match.group(2)!.toUpperCase()}';
    setState(() => _contacts[id] = match.group(1)!);
    _openChat(id, _contacts[id]!);
  }

  void _openChat(String id, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          identity: widget.identity,
          transport: _transport,
          conversationId: id,
          contactName: name,
        ),
      ),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Vibe Chat', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              icon: const Icon(Icons.settings_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (_) => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Your Vibe ID'),
                  content: SelectableText(widget.identity.displayId),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                ),
              ),
              itemBuilder: (_) => const [PopupMenuItem(value: 'id', child: Text('My Vibe ID'))],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6558D3), Color(0xFF9389ED)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('YOUR VIBE ID', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 5),
                Text(widget.identity.displayId,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('Username-first. No number needed.', style: TextStyle(color: Colors.white70)),
              ]),
            ),
            Expanded(
              child: _recent.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.chat_bubble_outline, size: 54, color: Colors.black26),
                        const SizedBox(height: 12),
                        const Text('Your conversations will appear here.'),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(onPressed: _addContact, icon: const Icon(Icons.person_add_alt_1), label: const Text('Start a chat')),
                      ]),
                    )
                  : ListView(
                      children: _recent.map((row) {
                        final id = row['conversation_id']! as String;
                        final name = _contacts[id] ?? id;
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: const Color(0xFFE8E5FC), child: Text(name.characters.first.toUpperCase())),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(row['body']! as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _openChat(id, name),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addContact,
          child: const Icon(Icons.add_comment_rounded),
        ),
      );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.identity,
    required this.transport,
    required this.conversationId,
    required this.contactName,
  });
  final LocalIdentity identity;
  final InternetTransport transport;
  final String conversationId;
  final String contactName;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _db = LocalDatabase();
  InternetTransport get _transport => widget.transport;
  final _moods = MoodDetector();
  final _media = MoodMediaService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<ChatMessage>? _subscription;
  StreamSubscription<MessageStatusUpdate>? _statusSubscription;
  List<ChatMessage> _messages = [];
  String _backgroundMood = 'neutral';

  @override
  void initState() {
    super.initState();
    _load();
    _subscription = _transport.incomingMessages.listen(_receive);
    _statusSubscription = _transport.statusUpdates.listen(_updateMessageStatus);
  }

  Future<void> _load() async {
    final messages = await _db.messagesFor(widget.conversationId);
    if (mounted) setState(() => _messages = messages);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final mood = _moods.detect(text);
    final message = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      conversationId: widget.conversationId,
      senderId: widget.identity.userId,
      body: text,
      moodId: mood,
      soundId: mood,
      createdAt: DateTime.now(),
      isOutgoing: true,
      status: 'sending',
    );
    _input.clear();
    await _db.insertMessage(message);
    if (mounted) setState(() => _messages = [..._messages, message]);
    await _onNewMood(mood, soundId: message.soundId);
    try {
      await _transport.send(message);
    } catch (_) {
      await _db.updateStatus(message.id, 'failed');
      _updateMessageStatus(MessageStatusUpdate(message.id, 'failed'));
    }
    _jumpToBottom();
  }

  void _updateMessageStatus(MessageStatusUpdate update) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((message) => message.id == update.messageId
          ? ChatMessage(
              id: message.id, conversationId: message.conversationId,
              senderId: message.senderId, body: message.body, moodId: message.moodId,
              soundId: message.soundId, createdAt: message.createdAt,
              isOutgoing: message.isOutgoing, status: update.status)
          : message).toList();
    });
    _db.updateStatus(update.messageId, update.status);
  }

  Future<void> _receive(ChatMessage message) async {
    if (message.conversationId != widget.conversationId) return;
    await _db.insertMessage(message);
    await _onNewMood(message.moodId, soundId: message.soundId);
    if (mounted) setState(() => _messages = [..._messages, message]);
    _jumpToBottom();
  }

  Future<void> _onNewMood(String mood, {String? soundId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('backgrounds_on') != false && mounted) {
      setState(() => _backgroundMood = mood);
    }
    await _media.play(soundId ?? mood);
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _statusSubscription?.cancel();
    _media.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.contactName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const Text('Vibe chat', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _MoodBackground(mood: _backgroundMood)),
            Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return Align(
                        alignment: message.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: message.isOutgoing ? const Color(0xFFDCD7FF) : Colors.white.withValues(alpha: .94),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(17),
                              topRight: const Radius.circular(17),
                              bottomLeft: Radius.circular(message.isOutgoing ? 17 : 4),
                              bottomRight: Radius.circular(message.isOutgoing ? 4 : 17),
                            ),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Align(alignment: Alignment.centerLeft, child: Text(message.body, style: const TextStyle(fontSize: 15))),
                            const SizedBox(height: 4),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(
                                '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 10, color: Colors.black54),
                              ),
                              if (message.isOutgoing) ...[
                                const SizedBox(width: 5),
                                Text(
                                  message.status == 'delivered' ? '✓✓' :
                                      message.status == 'sent' ? '✓' :
                                      message.status == 'failed' ? '!' : '…',
                                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                                ),
                              ],
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    color: Colors.white.withValues(alpha: .94),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: 'Message',
                            filled: true,
                            fillColor: const Color(0xFFF2F1F7),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _send,
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF6558D3), foregroundColor: Colors.white),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _MoodBackground extends StatelessWidget {
  const _MoodBackground({required this.mood});
  final String mood;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: Image.asset(
          'assets/memes/$mood.gif',
          key: ValueKey(mood),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFFECEAF5),
            key: ValueKey('fallback-$mood'),
          ),
        ),
      );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _muted = false;
  bool _sounds = true;
  bool _backgrounds = true;
  double _volume = .7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _muted = prefs.getBool('muted') ?? false;
      _sounds = prefs.getBool('sounds_on') ?? true;
      _backgrounds = prefs.getBool('backgrounds_on') ?? true;
      _volume = prefs.getDouble('volume') ?? .7;
    });
  }

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is double) await prefs.setDouble(key, value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          SwitchListTile(
            title: const Text('Mute'),
            subtitle: const Text('Silence all mood sounds'),
            value: _muted,
            onChanged: (v) { setState(() => _muted = v); _save('muted', v); },
          ),
          SwitchListTile(
            title: const Text('Sounds'),
            subtitle: const Text('Play mood sound effects'),
            value: _sounds,
            onChanged: (v) { setState(() => _sounds = v); _save('sounds_on', v); },
          ),
          ListTile(
            title: const Text('Volume'),
            subtitle: Slider(
              value: _volume,
              onChanged: (v) { setState(() => _volume = v); _save('volume', v); },
            ),
          ),
          SwitchListTile(
            title: const Text('Mood backgrounds'),
            subtitle: const Text('Change chat wallpaper with the message mood'),
            value: _backgrounds,
            onChanged: (v) { setState(() => _backgrounds = v); _save('backgrounds_on', v); },
          ),
        ]),
      );
}
