# Vibe Chat

Android-first username-based Flutter chat. User identities are generated on-device; message history and contacts stay in local SQLite. No phone numbers or central user database.

## Run the friend-request build
1. Install Flutter stable and Android SDK.
2. Generate the Android runner once: `flutter create --platforms=android .`
3. Merge the camera permission and `vibechat://add` intent-filter from `docs/android-manifest-snippet.xml` into `android/app/src/main/AndroidManifest.xml`.
4. Run `flutter pub get`.
5. Start the relay: `cd relay && npm install && npm start`.
6. Run: `flutter run -t lib/main_friend.dart --dart-define=VIBE_RELAY_URL=ws://10.0.2.2:8787` (Android emulator). Physical phones should use a reachable LAN IP or deployed WSS URL.

The original `lib/main.dart` entrypoint and chat UI are preserved. The friend-request experience is currently launched through `lib/main_friend.dart` so the existing entrypoint can be compared and rolled back without losing the new work.

## Friend identity and privacy
- My ID card displays `username#XXXX` and a QR containing the username, Ed25519 signing public key, X25519 encryption public key, the Ed25519 signature binding those keys, and relay URL.
- The share link uses `vibechat://add?... `; pasted IDs are resolved through the relay's temporary public-key directory.
- The four-character code is the first four hex characters of SHA-256(Ed25519 public key). A typed ID is not trusted until the relay returns the matching signed key bundle.
- Contacts and trust states are stored locally in SQLite. The relay stores no user database; its public-key directory, sessions and encrypted offline queues are RAM-only.
- New contacts remain requested until the recipient accepts. Only accepted contacts can open chats.
- Blocked and key-changed contacts have incoming envelopes dropped before decryption. Sending is blocked while a key change awaits confirmation.
- A username collision with a different Vibe ID is shown as a warning.

## Android manifest configuration
The generated Android runner must include the camera permission and deep-link intent filter shown in `docs/android-manifest-snippet.xml`. App links are not HTTPS verified links; they are a custom scheme handled by the installed app.

## Existing chat and relay tests
With the relay running: `cd relay && npm run test:two-clients`.
Flutter tests: `flutter test`.

## Architecture notes and limitations
- Ed25519 signs a challenge bound to the username and X25519 public key. X25519 derives a shared secret; XChaCha20-Poly1305 encrypts text, mood ID and sound ID.
- `InternetTransport` implements `MessageTransport` and reconnects with exponential backoff.
- Relay queue TTL is capped at 24 hours; queues disappear when the process restarts. Limits: 32 KiB envelope, 100 queued per recipient, 60 messages/minute/connection.
- The four-character suffix is collision-prone and should be expanded before public production.
- ID-only lookup works only after the person has connected to the same currently running relay at least once.
- A relay restart clears its in-memory directory and queued messages.
- The QR invite currently advertises one relay URL and one device keypair; multi-device identity and key recovery are not implemented.
- Review the cryptographic protocol before public production. This MVP does not yet provide forward secrecy or a formal audited protocol.
