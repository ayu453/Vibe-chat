# Vibe Chat

Android-first username-based Flutter chat. User identities are generated on-device; message history and contacts stay in local SQLite. No phone numbers or central user database.

## Run the friend-request build
1. Install Flutter stable and Android SDK.
2. Generate the Android runner once: `flutter create --platforms=android .`
3. Merge the camera permission and `vibechat://add` intent-filter from `docs/android-manifest-snippet.xml` into `android/app/src/main/AndroidManifest.xml`.
4. Run `flutter pub get`.
5. Start the relay: `cd relay && npm install && npm start`.
6. Run: `flutter run --dart-define=VIBE_RELAY_URL=ws://10.0.2.2:8787` (Android emulator). Physical phones should use a reachable LAN IP or deployed WSS URL.

The original chat, onboarding and settings implementation is preserved in `lib/legacy_main.dart`; `lib/main.dart` now launches the new friend-first home and reuses the existing onboarding and chat screen.

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
With the relay running: `cd relay && npm run test:two-clients`; mesh relay router: `cd relay && npm run test:mesh-router`.
Flutter tests: `flutter test`.

## Store-and-forward mesh (foundation in progress)
- Mesh packets use only `id`, pairwise daily `tag`, `ciphertext`, `createdAt`, `expiresAt`, `hopCount` and `copiesLeft`; sender and recipient IDs are not relay envelope fields.
- Route tags are HMAC-SHA-256 values derived from the X25519 pairwise shared secret and UTC day. Clients subscribe to today's and yesterday's tags to cover midnight rollover. Never derive tags from public keys.
- The relay mesh router stores opaque envelopes in RAM (20 MB cap), rejects duplicates and expired packets, and enforces 32 KiB, 48-hour, 8-hop, 6-copy and per-peer rate limits. Relay memory is volatile and is not a durable backup.
- SQLite outbox support and a deterministic A-B-C-D-E simulator are included as a foundation. The simulator is not a Bluetooth radio test.
- Android nearby radio discovery/transport is wired through the Android-only Nearby Connections plugin; Android permissions are listed in `docs/android-manifest-snippet.xml`. Carrier mode is enabled by default when the Mesh Debug screen is opened, can be switched off, and can be restricted to charging. It still requires two-physical-device testing and a generated Android runner. iOS support is not claimed.
- Nearby discovery uses a 15-second scan / 45-second pause duty cycle while advertising remains available. The carrier screen reads battery level/state, pauses below 15%, and supports carry-only-while-charging. Background/foreground-service scheduling and real device testing remain follow-up work.
- A five-node simulation proves protocol flow only; it does not guarantee real-world range, delivery time or delivery success.

## Architecture notes and limitations
- Ed25519 signs a challenge bound to the username and X25519 public key. X25519 derives a shared secret; XChaCha20-Poly1305 encrypts text, mood ID and sound ID.
- `InternetTransport` implements `MessageTransport` and reconnects with exponential backoff.
- Relay queue TTL is capped at 24 hours; queues disappear when the process restarts. Limits: 32 KiB envelope, 100 queued per recipient, 60 messages/minute/connection.
- The four-character suffix is collision-prone and should be expanded before public production.
- ID-only lookup works only after the person has connected to the same currently running relay at least once.
- A relay restart clears its in-memory directory and queued messages.
- The QR invite currently advertises one relay URL and one device keypair; multi-device identity and key recovery are not implemented.
- Review the cryptographic protocol before public production. This MVP does not yet provide forward secrecy or a formal audited protocol.

 
## Offline multilingual mood and receiver media packs
- MoodDetector keeps its original detect(String) method and adds confidence-aware results. It loads bundled JSON lexicons for English, Hindi (Devanagari and romanized Hinglish), Spanish, French, Portuguese, Arabic, Russian, Indonesian, Bengali and Turkish.
- Emoji, punctuation, capitalization and elongated-word rules run locally. The last three local messages can reduce confidence for nervous laughter or ambiguous replies after conflict. Low-confidence results do not trigger audio.
- No message text is sent to a cloud model for mood detection. A disabled TFLite extension point is present; no TFLite model or runtime is bundled in this change.
- Receiver-selected sound/background packs are defined by manifest files. Messages carry mood identifiers, not media files. Starter pack manifests intentionally contain no sound/song/GIF binaries; add only original or licensed media before release.
- The meme pack reserves an oops_fahhh.mp3 slot for an original/licensed oops sound. Song snippets are limited to ten seconds and played at reduced volume.
- App settings include mute, app-level Do Not Disturb, quiet hours, receiver pack selection, low-data/battery saver and reduce-motion preferences. Chat-specific mute, important-moods-only and quiet hours are stored locally.
- Automated language examples are in test/data/mood_samples.json. Run flutter test test/services/mood_detector_multilingual_test.dart to print per-language and total accuracy. This is a curated smoke-test set, not a scientific model benchmark.
- Encrypted local backup/restore is implemented with PBKDF2-HMAC-SHA256 and AES-256-GCM; the user saves the file and password themselves. Android system-level silent/DND state integration, actual licensed media, large-text QA and physical-device validation remain release tasks; see docs/RELEASE_CHECKLIST.md.
- The app follows system dark/light theme. Onboarding explains Vibe ID, QR adding, Nearby and carrier mode; Settings includes media-license status and accessibility/battery options.
