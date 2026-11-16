import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'models/chat_message.dart';
import 'services/identity_service.dart';
import 'services/internet_transport.dart';
import 'services/local_database.dart';
import 'services/message_transport.dart';
import 'services/mood_detector.dart';
import 'services/mood_media_service.dart';
import 'services/local_backup_service.dart';

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
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupRestoreScreen())),
                    child: const Text('Restore encrypted backup'),
                  ),
                  const SizedBox(height: 14),
                  const Text('Your keypair is generated on this device. Your identity stays local.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 22),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                        Text('How Vibe Chat works', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 10),
                        Text('• Your username creates a Vibe ID. No phone number or account is needed.'),
                        SizedBox(height: 8),
                        Text('• Add friends by scanning their QR code or sharing your ID.'),
                        SizedBox(height: 8),
                        Text('• Nearby mode can pass encrypted messages between phones that are close to each other.'),
                        SizedBox(height: 8),
                        Text('• Carrier mode lets your phone carry encrypted packets for others. Carriers cannot read message text.'),
                        SizedBox(height: 8),
                        Text('• Mood detection runs on this phone. Message text is not sent to a cloud mood service.'),
                      ]),
                    ),
                  ),
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
    unawaited(_moods.initialize());
    _load();
    _subscription = _transport.incomingMessages.listen(_receive);
    _statusSubscription = _transport.statusUpdates.listen(_updateMessageStatus);
  }

  Future<void> _load() async {
    final messages = await _db.messagesFor(widget.conversationId);
    if (mounted) setState(() => _messages = messages);
  }

  Future<void> _send() async {
    final contact = await _db.contact(widget.conversationId);
    if (contact == null || contact['status'] != 'accepted' || (contact['key_changed'] as int? ?? 0) == 1) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    await _moods.initialize();
    final contextMessages = _messages.skip(_messages.length > 3 ? _messages.length - 3 : 0).map((item) => item.body).toList();
    final moodResult = _moods.detectDetailed(text, recentMessages: contextMessages);
    final mood = moodResult.mood;
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
    await _onNewMood(mood, soundId: message.soundId, playSound: false);
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
    if (message.body.startsWith('vibe-control:')) return;
    if (await _db.isBlocked(message.conversationId)) return;
    final contact = await _db.contact(message.conversationId);
    if (contact == null || contact['status'] != 'accepted' || (contact['key_changed'] as int? ?? 0) == 1) return;
    await _moods.initialize();
    final contextMessages = _messages.skip(_messages.length > 3 ? _messages.length - 3 : 0).map((item) => item.body).toList();
    final localMood = _moods.detectDetailed(message.body, recentMessages: contextMessages);
    await _db.insertMessage(message);
    await _onNewMood(localMood.mood, soundId: localMood.mood, playSound: localMood.shouldPlaySound);
    if (mounted) setState(() => _messages = [..._messages, message]);
    _jumpToBottom();
  }

  Future<void> _onNewMood(String mood, {String? soundId, bool playSound = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('backgrounds_on') != false && mounted) setState(() => _backgroundMood = mood);
    if (playSound && mood != 'neutral') {
      await _media.play(soundId ?? mood, conversationId: widget.conversationId);
    }
  }

  Future<void> _showChatSoundSettings() async {
    final prefs = await SharedPreferences.getInstance();
    var muted = prefs.getBool('chat_mute_${widget.conversationId}') ?? false;
    var important = prefs.getBool('chat_important_${widget.conversationId}') ?? false;
    var quietStart = prefs.getInt('chat_quiet_start_${widget.conversationId}');
    var quietEnd = prefs.getInt('chat_quiet_end_${widget.conversationId}');
    TimeOfDay? toTime(int? minute) => minute == null ? null : TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
    int fromTime(TimeOfDay value) => value.hour * 60 + value.minute;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('${widget.contactName} preferences'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(title: const Text('Mute this chat'), value: muted, onChanged: (v) => setDialogState(() => muted = v)),
          SwitchListTile(title: const Text('Important moods only'), value: important, onChanged: (v) => setDialogState(() => important = v)),
          ListTile(title: const Text('Quiet hours start'), subtitle: Text(toTime(quietStart)?.format(context) ?? 'Not set'),
            trailing: const Icon(Icons.schedule), onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: toTime(quietStart) ?? const TimeOfDay(hour: 22, minute: 0));
              if (picked != null) setDialogState(() => quietStart = fromTime(picked));
            }),
          ListTile(title: const Text('Quiet hours end'), subtitle: Text(toTime(quietEnd)?.format(context) ?? 'Not set'),
            trailing: const Icon(Icons.schedule), onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: toTime(quietEnd) ?? const TimeOfDay(hour: 7, minute: 0));
              if (picked != null) setDialogState(() => quietEnd = fromTime(picked));
            }),
          TextButton(onPressed: () => setDialogState(() { quietStart = null; quietEnd = null; }), child: const Text('Clear quiet hours')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            await prefs.setBool('chat_mute_${widget.conversationId}', muted);
            await prefs.setBool('chat_important_${widget.conversationId}', important);
            if (quietStart == null || quietEnd == null) {
              await prefs.remove('chat_quiet_start_${widget.conversationId}');
              await prefs.remove('chat_quiet_end_${widget.conversationId}');
            } else {
              await prefs.setInt('chat_quiet_start_${widget.conversationId}', quietStart!);
              await prefs.setInt('chat_quiet_end_${widget.conversationId}', quietEnd!);
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('Save')),
        ],
      ),
    ));
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
          actions: [IconButton(tooltip: 'Chat preferences', onPressed: _showChatSoundSettings, icon: const Icon(Icons.tune))],
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

class _MoodBackground extends StatefulWidget {
  const _MoodBackground({required this.mood});
  final String mood;
  @override
  State<_MoodBackground> createState() => _MoodBackgroundState();
}

class _MoodBackgroundState extends State<_MoodBackground> {
  String? _asset;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _MoodBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saver = prefs.getBool('battery_saver') == true || prefs.getBool('low_data') == true;
    final reduceMotion = prefs.getBool('reduce_motion') == true;
    String? asset;
    if (!saver) {
      final pack = prefs.getString('meme_pack') ?? 'meme';
      try {
        final manifest = jsonDecode(await rootBundle.loadString('assets/meme_packs/$pack/manifest.json')) as Map<String, dynamic>;
        final backgrounds = manifest['backgrounds'] as Map<String, dynamic>? ?? {};
        final entry = backgrounds[widget.mood];
        if (entry is String && entry.isNotEmpty) asset = entry;
        if (entry is List && entry.isNotEmpty && entry.first is String) asset = entry.first as String;
      } catch (_) {}
      asset ??= 'assets/memes/${widget.mood}.gif';
    }
    if (!mounted) return;
    setState(() { _asset = asset; _reduceMotion = reduceMotion; });
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 500),
    child: _asset == null
      ? Container(key: ValueKey('empty-${widget.mood}'), color: const Color(0xFFECEAF5))
      : Stack(key: ValueKey(_asset), fit: StackFit.expand, children: [
          Image.asset(_asset!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFECEAF5))),
          Container(color: Colors.black.withValues(alpha: .28)),
        ]),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _muted = false, _sounds = true, _backgrounds = true, _dnd = false;
  bool _reduceMotion = false, _batterySaver = false, _lowData = false;
  double _volume = .7;
  String _soundPack = 'meme', _memePack = 'meme';
  int? _quietStart, _quietEnd;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _muted = prefs.getBool('muted') ?? false;
      _sounds = prefs.getBool('sounds_on') ?? true;
      _backgrounds = prefs.getBool('backgrounds_on') ?? true;
      _volume = prefs.getDouble('volume') ?? .7;
      _dnd = prefs.getBool('dnd_on') ?? false;
      _reduceMotion = prefs.getBool('reduce_motion') ?? false;
      _batterySaver = prefs.getBool('battery_saver') ?? false;
      _lowData = prefs.getBool('low_data') ?? false;
      _soundPack = prefs.getString('sound_pack') ?? 'meme';
      _memePack = prefs.getString('meme_pack') ?? 'meme';
      _quietStart = prefs.getInt('quiet_start_minute');
      _quietEnd = prefs.getInt('quiet_end_minute');
    });
  }

  Future<void> _saveBool(String key, bool value) async => (await SharedPreferences.getInstance()).setBool(key, value);
  Future<void> _saveDouble(String key, double value) async => (await SharedPreferences.getInstance()).setDouble(key, value);
  Future<void> _saveString(String key, String value) async => (await SharedPreferences.getInstance()).setString(key, value);

  Future<void> _pickQuietTime(bool start) async {
    final current = start ? _quietStart : _quietEnd;
    final initial = current == null ? TimeOfDay(hour: start ? 22 : 7, minute: 0) : TimeOfDay(hour: current ~/ 60, minute: current % 60);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    final prefs = await SharedPreferences.getInstance();
    setState(() { if (start) { _quietStart = minute; } else { _quietEnd = minute; } });
    await prefs.setInt(start ? 'quiet_start_minute' : 'quiet_end_minute', minute);
  }

  String _formatMinute(int? value) => value == null ? 'Not set' : TimeOfDay(hour:value ~/ 60, minute:value % 60).format(context);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      SwitchListTile(title: const Text('Mute'), subtitle: const Text('Silence all mood sounds'), value: _muted,
        onChanged: (v) { setState(() => _muted = v); _saveBool('muted', v); }),
      SwitchListTile(title: const Text('Sounds'), subtitle: const Text('Play receiver-selected mood clips'), value: _sounds,
        onChanged: (v) { setState(() => _sounds = v); _saveBool('sounds_on', v); }),
      SwitchListTile(title: const Text('Do Not Disturb'), subtitle: const Text('Pause all in-app mood audio'), value: _dnd,
        onChanged: (v) { setState(() => _dnd = v); _saveBool('dnd_on', v); }),
      ListTile(title: const Text('Sound pack'), subtitle: const Text('Each receiver chooses what they hear'),
        trailing: DropdownButton<String>(value:_soundPack, items: const [
          DropdownMenuItem(value:'meme',child:Text('Meme')), DropdownMenuItem(value:'calm',child:Text('Calm')),
          DropdownMenuItem(value:'bollywood-style',child:Text('Bollywood style')), DropdownMenuItem(value:'anime-style',child:Text('Anime style')),
        ], onChanged:(v) { if(v==null)return; setState(()=>_soundPack=v); _saveString('sound_pack',v); })),
      ListTile(title: const Text('Volume'), subtitle: Slider(value:_volume, onChanged:(v){setState(()=>_volume=v);_saveDouble('volume',v);})),
      SwitchListTile(title: const Text('Mood backgrounds'), subtitle: const Text('Use receiver-selected mood wallpapers'), value:_backgrounds,
        onChanged:(v){setState(()=>_backgrounds=v);_saveBool('backgrounds_on',v);}),
      ListTile(title: const Text('Background pack'), trailing: DropdownButton<String>(value:_memePack, items: const [
        DropdownMenuItem(value:'meme',child:Text('Meme')), DropdownMenuItem(value:'calm',child:Text('Calm')),
        DropdownMenuItem(value:'bollywood-style',child:Text('Bollywood style')), DropdownMenuItem(value:'anime-style',child:Text('Anime style')),
      ], onChanged:(v){if(v==null)return;setState(()=>_memePack=v);_saveString('meme_pack',v);})),
      ListTile(title: const Text('Quiet hours start'), subtitle: Text(_formatMinute(_quietStart)), trailing: const Icon(Icons.schedule), onTap:()=>_pickQuietTime(true)),
      ListTile(title: const Text('Quiet hours end'), subtitle: Text(_formatMinute(_quietEnd)), trailing: const Icon(Icons.schedule), onTap:()=>_pickQuietTime(false)),
      SwitchListTile(title: const Text('Battery saver'), subtitle: const Text('Disable animated backgrounds'), value:_batterySaver,
        onChanged:(v){setState(()=>_batterySaver=v);_saveBool('battery_saver',v);}),
      SwitchListTile(title: const Text('Low data mode'), subtitle: const Text('Disable animated backgrounds'), value:_lowData,
        onChanged:(v){setState(()=>_lowData=v);_saveBool('low_data',v);}),
      SwitchListTile(title: const Text('Reduce motion'), subtitle: const Text('Use instant background changes'), value:_reduceMotion,
        onChanged:(v){setState(()=>_reduceMotion=v);_saveBool('reduce_motion',v);}),
      ListTile(
        leading: const Icon(Icons.backup_outlined),
        title: const Text('Encrypted local backup'),
        subtitle: const Text('Export or restore chats and identity keys'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupRestoreScreen())),
      ),
      ListTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('Media licenses'),
        subtitle: const Text('Sources and license status for sounds, songs and backgrounds'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaLicensesScreen())),
      ),
    ]),
  );
}

class MediaLicensesScreen extends StatelessWidget {
  const MediaLicensesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Media licenses')),
    body: ListView(padding: const EdgeInsets.all(18), children: const [
      Text('No third-party sound, song or meme files are bundled in the starter packs.',
        style: TextStyle(fontWeight: FontWeight.w600)),
      SizedBox(height: 14),
      ListTile(title: Text('Meme sound pack'), subtitle: Text('Manifest ready; audio files not yet supplied. Add an original or licensed clip and record its creator, source and license.')),
      ListTile(title: Text('Calm sound pack'), subtitle: Text('Manifest ready; no audio files supplied.')),
      ListTile(title: Text('Bollywood-style pack'), subtitle: Text('Use only original compositions or appropriately licensed recordings. No film soundtrack/dialogue clips.')),
      ListTile(title: Text('Anime-style pack'), subtitle: Text('Use only original compositions or appropriately licensed recordings. No anime soundtrack/dialogue clips.')),
      ListTile(title: Text('Song snippets'), subtitle: Text('Only original/licensed tracks; playback is limited to ten seconds with reduced volume.')),
      ListTile(title: Text('Meme backgrounds'), subtitle: Text('Pack manifests are ready; image/GIF files and per-file license records are still required.')),
      SizedBox(height: 8),
      Text('Before release, add the exact source URL, creator, license name, attribution text and proof of permission for every media file.'),
    ]),
  );
}

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});
  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final _password = TextEditingController();
  final _backup = LocalBackupService();
  bool _busy = false;
  String? _status;

  @override
  void dispose() { _password.dispose(); super.dispose(); }

  Future<void> _export() async {
    setState(() { _busy = true; _status = null; });
    try {
      final bytes = await _backup.createBackup(_password.text);
      await Share.shareXFiles([
        XFile.fromData(bytes, name: 'vibe-chat-backup.vibe', mimeType: 'application/octet-stream'),
      ], text: 'Encrypted Vibe Chat backup. Keep your password safe; it cannot be recovered.');
      if (mounted) setState(() => _status = 'Encrypted backup prepared. Save the file somewhere you control.');
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('ArgumentError: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() { _busy = true; _status = null; });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['vibe'], withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) throw StateError('Could not read the selected backup file.');
      await _backup.restoreBackup(bytes, _password.text);
      if (!mounted) return;
      setState(() => _status = 'Backup restored. Vibe Chat will close so it can reload the restored identity and chats.');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await SystemNavigator.pop();
    } catch (error) {
      if (mounted) setState(() => _status = error.toString().replaceFirst('ArgumentError: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Encrypted local backup')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Your chats, contacts and identity keys are encrypted on this device before you save the file. Nothing is uploaded to a cloud service.'),
      const SizedBox(height: 16),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Backup password',
          helperText: 'Use at least 10 characters. The password is not recoverable.',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _busy ? null : _export,
        icon: const Icon(Icons.save_alt),
        label: const Text('Create encrypted backup'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _busy ? null : _restore,
        icon: const Icon(Icons.restore),
        label: const Text('Restore from backup file'),
      ),
      if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (_status != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_status!)),
    ]),
  );
}
