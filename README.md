# Vibe Chat

Android-first, username-based Flutter chat client. Identity is generated on-device and stored locally; messages are stored in SQLite. No phone-number identity, cloud database, or backend is included in this MVP.

## MVP architecture
- Ed25519 device keypair; public-key hash supplies the four-character ID suffix.
- Private key stored using platform secure storage.
- SQLite stores message text and its mood ID.
- `MoodDetector` is deterministic and replaceable.
- `MessageTransport` is the seam for future internet, Bluetooth, or mesh adapters. `FakeLocalTransport` is a local no-network placeholder, not cross-device messaging.
- Mood sounds and backgrounds are optional local assets; see each assets folder README.

## Run
1. Install Flutter stable and Android SDK.
2. Run `flutter pub get`.
3. Run `flutter run`.

This repository is an offline-first UI and local-storage MVP. Real device-to-device delivery, contact discovery, key verification, and production security review are future work.
