import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_chat/services/mood_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('offline multilingual mood sample accuracy', () async {
    final detector = MoodDetector();
    await detector.initialize();
    final data = jsonDecode(await File('test/data/mood_samples.json').readAsString()) as Map<String, dynamic>;
    var total = 0;
    var correct = 0;
    for (final entry in data.entries) {
      var languageCorrect = 0;
      final examples = entry.value as List<dynamic>;
      for (final raw in examples) {
        final sample = raw as Map<String, dynamic>;
        total++;
        if (detector.detectDetailed(sample['text'] as String).mood == sample['mood']) {
          correct++;
          languageCorrect++;
        }
      }
      // ignore: avoid_print
      print('${entry.key}: $languageCorrect/${examples.length} (${(languageCorrect * 100 / examples.length).toStringAsFixed(1)}%)');
    }
    // ignore: avoid_print
    print('TOTAL: $correct/$total (${(correct * 100 / total).toStringAsFixed(1)}%)');
    expect(data.length, 10);
    expect(total, greaterThanOrEqualTo(150));
    expect(correct / total, greaterThanOrEqualTo(0.80));
  });

  test('low confidence laughter after bad news is silent', () async {
    final detector = MoodDetector();
    await detector.initialize();
    final result = detector.detectDetailed('haha', recentMessages: ['I have bad news', 'my friend died']);
    expect(result.mood, 'funny');
    expect(result.confidence, lessThan(0.58));
    expect(result.shouldPlaySound, isFalse);
  });

  test('emoji and punctuation rules are local and deterministic', () async {
    final detector = MoodDetector();
    await detector.initialize();
    expect(detector.detectDetailed('😭').mood, 'sad');
    expect(detector.detectDetailed('😂').mood, 'funny');
    expect(detector.detectDetailed('WHAT???').mood, 'shock');
  });
}
