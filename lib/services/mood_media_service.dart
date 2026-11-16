import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MoodMediaService {
  MoodMediaService({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _songPlayer = AudioPlayer();
  final Random _random = Random();
  final Map<String, String> _lastClipByMood = {};
  Timer? _songTimer;
  DateTime? _lastPlayedAt;

  Future<void> play(
    String moodId, {
    String? conversationId,
    bool importantOnly = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('sounds_on') == false ||
        prefs.getBool('muted') == true ||
        prefs.getBool('dnd_on') == true) {
      await stop();
      return;
    }
    _songTimer?.cancel();
    await _songPlayer.stop();
    await _player.stop();
    if (conversationId != null) {
      if (prefs.getBool('chat_mute_$conversationId') == true) return;
      importantOnly = importantOnly || (prefs.getBool('chat_important_$conversationId') ?? false);
    }
    if (importantOnly && !_importantMoods.contains(moodId)) return;
    final chatStart = conversationId == null ? null : prefs.getInt('chat_quiet_start_$conversationId');
    final chatEnd = conversationId == null ? null : prefs.getInt('chat_quiet_end_$conversationId');
    final globalQuiet = _isQuietNow(DateTime.now(), prefs.getInt('quiet_start_minute'), prefs.getInt('quiet_end_minute'));
    final chatQuiet = _isQuietNow(DateTime.now(), chatStart, chatEnd);
    if (globalQuiet || chatQuiet) return;
    final now = DateTime.now();
    if (_lastPlayedAt != null && now.difference(_lastPlayedAt!) < const Duration(seconds: 2)) return;

    final pack = prefs.getString('sound_pack') ?? 'meme';
    final songClips = await _songsFor(pack, moodId);
    if (songClips.isNotEmpty) {
      await playSongSnippet(songClips[_random.nextInt(songClips.length)]);
      return;
    }
    final clips = await _clipsFor(pack, moodId);
    if (clips.isEmpty) return;
    final alternatives = clips.where((clip) => clip != _lastClipByMood[moodId]).toList();
    final pool = alternatives.isEmpty ? clips : alternatives;
    final clip = pool[_random.nextInt(pool.length)];

    await _player.setVolume((prefs.getDouble('volume') ?? 0.7).clamp(0.0, 1.0).toDouble());
    try {
      await _player.play(AssetSource(clip));
      _lastClipByMood[moodId] = clip;
      _lastPlayedAt = now;
    } catch (_) {
      // Missing optional/licensed media never blocks messaging.
    }
  }

  Future<List<String>> _songsFor(String pack, String mood) async {
    try {
      final raw = await _bundle.loadString('assets/sound_packs/$pack/manifest.json');
      final manifest = jsonDecode(raw) as Map<String, dynamic>;
      final songs = manifest['songs'] as Map<String, dynamic>? ?? {};
      return (songs[mood] as List<dynamic>? ?? const [])
          .whereType<String>().where((path) => path.trim().isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _clipsFor(String pack, String mood) async {
    try {
      final raw = await _bundle.loadString('assets/sound_packs/$pack/manifest.json');
      final manifest = jsonDecode(raw) as Map<String, dynamic>;
      final sounds = manifest['sounds'] as Map<String, dynamic>? ?? {};
      return (sounds[mood] as List<dynamic>? ?? const [])
          .whereType<String>().where((path) => path.trim().isNotEmpty).toList();
    } catch (_) {
      return ['sounds/$mood.mp3'];
    }
  }

  /// Songs are intentionally quieter than effects and stop after ten seconds.
  Future<void> playSongSnippet(String assetPath) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('sounds_on') == false || prefs.getBool('muted') == true ||
        prefs.getBool('dnd_on') == true) return;
    final now = DateTime.now();
    if (_lastPlayedAt != null && now.difference(_lastPlayedAt!) < const Duration(seconds: 2)) return;
    _songTimer?.cancel();
    await _player.stop();
    await _songPlayer.stop();
    final master = prefs.getDouble('volume') ?? 0.7;
    try {
      await _songPlayer.setVolume(0);
      await _songPlayer.play(AssetSource(assetPath));
      var step = 0;
      _songTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        step++;
        final progress = step / 20;
        final fade = progress < .2 ? progress / .2 : progress > .8 ? (1 - progress) / .2 : 1.0;
        await _songPlayer.setVolume((master * .35 * fade).clamp(0.0, 1.0).toDouble());
        if (step >= 20) {
          timer.cancel();
          await _songPlayer.stop();
        }
      });
      _lastPlayedAt = now;
    } catch (_) {}
  }

  bool _isQuietNow(DateTime now, int? start, int? end) {
    if (start == null || end == null || start == end) return false;
    final minute = now.hour * 60 + now.minute;
    return start < end ? minute >= start && minute < end : minute >= start || minute < end;
  }

  static const _importantMoods = {'sad','angry','oops','shock','win'};

  Future<void> stop() async {
    _songTimer?.cancel();
    await _player.stop();
    await _songPlayer.stop();
  }

  Future<void> dispose() async {
    _songTimer?.cancel();
    await _player.dispose();
    await _songPlayer.dispose();
  }
}
