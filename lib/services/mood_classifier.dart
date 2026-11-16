/// Optional TFLite integration point. Disabled by default: no model package
/// or model asset is loaded unless a future release supplies one explicitly.
abstract interface class OnDeviceMoodClassifier {
  Future<({String mood, double confidence})?> classify(String text);
}

class DisabledMoodClassifier implements OnDeviceMoodClassifier {
  const DisabledMoodClassifier();
  @override
  Future<({String mood, double confidence})?> classify(String text) async => null;
}

const bool tfliteMoodEnabled = bool.fromEnvironment(
  'VIBE_TFLITE_MOOD',
  defaultValue: false,
);
