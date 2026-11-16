import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_chat/services/mood_detector.dart';

void main() {
  final detector = MoodDetector();

  test('detects supported mood keywords and emojis', () {
    expect(detector.detect('That was hilarious 😂'), 'funny');
    expect(detector.detect('I miss you ❤️'), 'love');
    expect(detector.detect('We won the match 🏆'), 'win');
    expect(detector.detect('I am so angry 😡'), 'angry');
    expect(detector.detect('Nothing special today'), 'neutral');
  });
}
