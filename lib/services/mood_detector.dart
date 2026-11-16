class MoodDetector {
  static const moods = {
    'funny', 'sad', 'shock', 'win', 'love', 'angry',
    'scary', 'bored', 'party', 'oops', 'neutral',
  };

  String detect(String text) {
    final value = text.toLowerCase();
    if (_has(value, ['😂', '🤣', 'lol', 'haha', 'lmao', ' मज़ाक', 'joke'])) return 'funny';
    if (_has(value, ['😢', '😭', 'sad', 'cry', 'miss you', ' दुख'])) return 'sad';
    if (_has(value, ['😱', '😮', '😲', 'wow', 'what?!', 'omg', 'shocked'])) return 'shock';
    if (_has(value, ['🏆', '🎉', ' जीत', 'won', 'winner', 'congrats', 'समझ गया'])) return 'win';
    if (_has(value, ['❤️', '😍', '🥰', 'love', ' प्यार', 'miss u'])) return 'love';
    if (_has(value, ['😡', '🤬', 'angry', 'hate', 'furious', 'गुस्सा'])) return 'angry';
    if (_has(value, ['👻', '😨', '😰', 'scary', ' डर', 'creepy'])) return 'scary';
    if (_has(value, ['🥱', '😴', 'bored', 'boring', 'उबाऊ'])) return 'bored';
    if (_has(value, ['🥳', '🎊', '🪩', 'party', 'celebrate'])) return 'party';
    if (_has(value, ['😅', '🤦', 'oops', 'sorry', ' गलती', 'my bad'])) return 'oops';
    return 'neutral';
  }

  bool _has(String text, List<String> terms) =>
      terms.any((term) => text.contains(term));
}
