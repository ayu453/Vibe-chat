# Vibe Chat

Android-first, username-based Flutter chat client. Identity is generated on-device and stored locally; messages are stored in SQLite. No phone-number identity, cloud database, or backend is included in this MVP.

## MVP architecture
- Ed25519 device keypair; public-key hash supplies the four-character ID suffix.
- Private key stored using platform secure storage.
- SQLite stores message text and its mood ID.
- `MoodDetector` is deterministic and replaceable.
- `MessageTransport` is the seam for future internet, Bluetooth, or mesh adapters. `FakeLocalTransport` is a local no-network placeholder, not cross-device messaging.
- Mood media is loaded from local assets. The expected filenames and licensing guidance are documented in each assets folder; actual sound and meme files still need to be added.

## Run on Android
1. Install Flutter stable and Android SDK.
2. From the repository root, generate the Android runner once: `flutter create --platforms=android .`
3. Run `flutter pub get`.
4. Run `flutter run`.

## Checks
- `flutter analyze`
- `flutter test`

This repository is an offline-first UI and local-storage MVP. Real device-to-device delivery, contact discovery, key verification, media assets, and production security review are future work.
