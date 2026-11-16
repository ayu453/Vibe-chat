import 'dart:convert';
import 'package:flutter/services.dart';

class MoodDetectionResult {
  const MoodDetectionResult({required this.mood, required this.confidence, required this.language, this.reason = 'lexicon'});
  final String mood;
  final double confidence;
  final String language;
  final String reason;
  bool get shouldPlaySound => mood != 'neutral' && confidence >= 0.58;
}

/// Backwards-compatible offline detector. Call initialize() once before use.
class MoodDetector {
  static const moods = {'funny','sad','shock','win','love','angry','scary','bored','party','oops','neutral'};
  static const supportedLanguages = ['en','hi','es','fr','pt','ar','ru','id','bn','tr'];
  final AssetBundle _bundle;
  final Map<String, Map<String, List<String>>> _lexicons = {};
  bool _initialized = false;
  MoodDetector({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    for (final language in supportedLanguages) {
      try {
        final decoded = jsonDecode(await _bundle.loadString('assets/lexicons/$language.json')) as Map<String, dynamic>;
        final source = decoded['moods'] as Map<String, dynamic>;
        _lexicons[language] = {
          for (final entry in source.entries)
            entry.key: (entry.value as List<dynamic>).whereType<String>().toList(),
        };
      } catch (_) {}
    }
    _initialized = true;
  }

  String detect(String text) => detectDetailed(text).mood;

  MoodDetectionResult detectDetailed(String text, {List<String> recentMessages = const []}) {
    final value = _normalize(text);
    if (value.isEmpty) return const MoodDetectionResult(mood:'neutral', confidence:0, language:'und', reason:'empty');
    final rule = _detectRules(text, value);
    if (rule != null) return _applyContext(rule, recentMessages);
    var bestMood = 'neutral', bestLanguage = 'und';
    var bestScore = 0.0, secondScore = 0.0;
    for (final languageEntry in _lexicons.entries) {
      for (final moodEntry in languageEntry.value.entries) {
        for (final phrase in moodEntry.value) {
          final term = _normalize(phrase);
          if (term.isEmpty || !_containsTerm(value, term)) continue;
          final score = term.contains(' ') ? 0.82 : 0.76;
          if (score > bestScore) {
            secondScore = bestScore;
            bestScore = score;
            bestMood = moodEntry.key;
            bestLanguage = languageEntry.key;
          } else if (score > secondScore && moodEntry.key != bestMood) {
            secondScore = score;
          }
        }
      }
    }
    if (bestScore == 0) return const MoodDetectionResult(mood:'neutral', confidence:0.42, language:'und', reason:'unsure');
    var confidence = bestScore;
    if (secondScore >= bestScore) confidence = 0.55;
    if (RegExp(r'(.)\1{2,}', unicode:true).hasMatch(value)) confidence = (confidence + 0.04).clamp(0.0, 0.99).toDouble();
    return _applyContext(MoodDetectionResult(mood:bestMood, confidence:confidence, language:bestLanguage),recentMessages);
  }

  MoodDetectionResult? _detectRules(String original, String value) {
    const emojiRules = <String, String>{
      '😂':'funny','🤣':'funny','😆':'funny','😹':'funny',
      '😭':'sad','😢':'sad','😿':'sad',
      '😱':'shock','😮':'shock','😲':'shock','🤯':'shock',
      '❤️':'love','😍':'love','🥰':'love','😘':'love',
      '😡':'angry','🤬':'angry','😠':'angry',
      '🥳':'party','🎉':'party','🎊':'party',
      '😅':'oops','🤦':'oops','👻':'scary','😨':'scary','😰':'scary',
      '🥱':'bored','😴':'bored','🏆':'win','🥇':'win',
    };
    const emojiConfidence = <String,double>{'funny':.99,'sad':.99,'shock':.98,'love':.98,'angry':.98,'party':.98,'oops':.91,'scary':.96,'bored':.96,'win':.95};
    for (final entry in emojiRules.entries) {
      if (original.contains(entry.key)) {
        return MoodDetectionResult(mood:entry.value,confidence:emojiConfidence[entry.value]!,language:'und',reason:'emoji');
      }
    }
    if (RegExp(r'\?{3,}').hasMatch(original)) return const MoodDetectionResult(mood:'shock',confidence:.68,language:'und',reason:'punctuation');
    if (RegExp(r'!{3,}').hasMatch(original)) return const MoodDetectionResult(mood:'shock',confidence:.64,language:'und',reason:'punctuation');
    final letters = original.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.length >= 4 && letters == letters.toUpperCase() && letters != letters.toLowerCase()) {
      return const MoodDetectionResult(mood:'angry',confidence:.60,language:'und',reason:'caps');
    }
    if (RegExp(r'(.)\1{3,}',unicode:true).hasMatch(value) && RegExp(r'\b(no+|nah+|ugh+)\b').hasMatch(value)) {
      return const MoodDetectionResult(mood:'angry',confidence:.64,language:'und',reason:'elongation');
    }
    return null;
  }

  MoodDetectionResult _applyContext(MoodDetectionResult result, List<String> recentMessages) {
    if (recentMessages.isEmpty) return result;
    final context = recentMessages.take(3).map(_normalize).join(' ');
    final negative = RegExp(r'\b(bad news|died|death|fail|failed|problem|fight|argue|break up|dukh|bura|mar gaya|nuksan|triste|mauvaise nouvelle|morreu|смерть|плохо|sedih|meninggal|দুঃখ|খারাপ|üzgün|kavga)\b',caseSensitive:false).hasMatch(context);
    final conflict = RegExp(r'\b(fight|argue|angry|mad|gussa|झगड़ा|enojado|colère|briga|ссора|marah|রাগ|kavga)\b',caseSensitive:false).hasMatch(context);
    if (negative && result.mood == 'funny') {
      return MoodDetectionResult(mood:result.mood,confidence:(result.confidence * .48).clamp(0.0,.49).toDouble(),language:result.language,reason:'context_uncertain');
    }
    if (conflict && result.mood == 'neutral') return MoodDetectionResult(mood:'neutral',confidence:.35,language:result.language,reason:'context_uncertain');
    return result;
  }

  String _normalize(String value) => value.toLowerCase().replaceAll('’',"'")
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+',unicode:true),' ')
      .replaceAll(RegExp(r'\s+'),' ').trim();

  bool _containsTerm(String text, String term) {
    if (term.contains(' ')) return text.contains(term);
    return RegExp(r'(^|\s)' + RegExp.escape(term) + r'($|\s)',unicode:true).hasMatch(text);
  }
}
