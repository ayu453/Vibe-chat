# Vibe Chat

Android-first username-based Flutter chat. User identities are generated on-device; message history stays in local SQLite.

## Run the app
1. Install Flutter stable and Android SDK.
2. Generate the Android runner once: `flutter create --platforms=android .`
3. Run `flutter pub get`.
4. Start the relay in another terminal: `cd relay && npm install && npm start`.
5. Default relay URL is `ws://localhost:8787`. Android emulators usually need `ws://10.0.2.2:8787`; physical phones need a reachable LAN IP or deployed WSS endpoint.
6. Override with `flutter run --dart-define=VIBE_RELAY_URL=ws://10.0.2.2:8787`.

## Two-client relay test
With the relay running: `cd relay && npm run test:two-clients`.

## Architecture
- Existing onboarding, chat UI, mood detection, mood media and SQLite remain.
- Ed25519 signs a challenge bound to the username and X25519 public key. X25519 derives a shared secret; XChaCha20-Poly1305 encrypts text, mood ID and sound ID.
- `InternetTransport` implements `MessageTransport` and reconnects with exponential backoff.
- Relay stores sessions, public-key directory entries, deduplication IDs and encrypted offline queues in RAM only.
- Relay queue TTL is capped at 24 hours; queues disappear when the process restarts. Limits: 32 KiB envelope, 100 queued per recipient, 60 messages/minute/connection.
- Relay cannot decrypt message content. It necessarily sees routing IDs, timing and ciphertext size.

## Important limitations
- A recipient must have connected to the same relay process at least once so its public encryption key is known. The key directory is RAM-only and resets on restart.
- Message statuses are sending, sent and delivered. Delivered means the relay handed the encrypted envelope to the recipient socket; it is not a read receipt.
- Four-character suffixes are collision-prone and should be expanded before public production.
- Review the cryptographic protocol and key verification before production. This MVP does not yet provide verified safety numbers, forward secrecy, multi-device identity, or a persistent contact-key directory.
- Use TLS/WSS in deployment. No message content is written to relay logs or disk.
