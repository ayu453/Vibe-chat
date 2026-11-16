import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MoodMediaService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> play(String moodId) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('sounds_on') == false || prefs.getBool('muted') == true) {
      await _player.stop();
      return;
    }
    await _player.stop();
    final volume = prefs.getDouble('volume') ?? 0.7;
    await _player.setVolume(volume);
    try {
      await _player.play(AssetSource('sounds/$moodId.mp3'));
    } catch (_) {
      // Placeholder assets are added by the media pack before release.
    }
  }

  Future<void> stop() => _player.stop();
  Future<void> dispose() => _player.dispose();
}
