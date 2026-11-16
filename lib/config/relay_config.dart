class RelayConfig {
  static const String relayUrl = String.fromEnvironment(
    'VIBE_RELAY_URL',
    defaultValue: 'ws://localhost:8787',
  );
}
