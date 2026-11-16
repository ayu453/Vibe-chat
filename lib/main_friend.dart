import 'package:flutter/material.dart';
import 'main.dart' hide main, VibeChatApp, AppGate, ChatListScreen;
import 'screens/friend_home_screen.dart';
import 'services/identity_service.dart';

void main() => runApp(const VibeChatFriendsApp());

class VibeChatFriendsApp extends StatelessWidget {
  const VibeChatFriendsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vibe Chat',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6558D3)),
      scaffoldBackgroundColor: const Color(0xFFF7F6FC),
    ),
    home: const FriendAppGate(),
  );
}

class FriendAppGate extends StatefulWidget {
  const FriendAppGate({super.key});
  @override
  State<FriendAppGate> createState() => _FriendAppGateState();
}

class _FriendAppGateState extends State<FriendAppGate> {
  final _identityService = IdentityService();
  LocalIdentity? _identity;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _identityService.load().then((identity) {
      if (!mounted) return;
      setState(() { _identity = identity; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_identity == null) {
      return OnboardingScreen(onCreated: (identity) => setState(() => _identity = identity));
    }
    return FriendHomeScreen(identity: _identity!);
  }
}
