# Vibe Chat release checklist

## Android permissions
- [ ] Camera is requested only when the user opens QR scanning to add a friend.
- [ ] Nearby Bluetooth/Wi-Fi discovery permissions are used by carrier mode to discover nearby Vibe Chat devices and transfer opaque encrypted envelopes. Explain each Android-version-specific prompt before requesting it.
- [ ] Normal chat and mood detection do not require contacts, phone, SMS, microphone or location permissions.
- [ ] Validate the final permission list against the generated Android runner and target SDK; test denial and revocation.

## Privacy policy points (verify against the production build)
- [ ] No phone-number account and no central user database.
- [ ] Identity keys, contacts, chat history and mood detection remain on-device.
- [ ] Mood detection is local; message text is not sent to a cloud model for mood analysis.
- [ ] Chat content is end-to-end encrypted. Relay/carriers handle ciphertext only; timing, packet size and routing metadata may remain observable.
- [ ] Relay offline queue is volatile RAM storage, expires within 24 hours, and is cleared on relay restart. Do not describe this as durable server storage.
- [ ] Nearby carrier mode is configurable; carriers forward opaque encrypted packets and cannot read message text.
- [ ] Backup is user-controlled and encrypted; the app does not upload it to cloud storage.
- [ ] Disclose any analytics, diagnostics, crash reporting or third-party SDKs added later.

## Play Store Data Safety (confirm from final build and SDK inventory)
- [ ] Do not submit guessed answers. Review dependencies, network requests and relay behavior.
- [ ] If no analytics/ads/crash SDK is present and no personal data is sent to the developer, document the evidence for each answer.
- [ ] Assess whether encrypted packets and routing/connection metadata count as collected data under current Play definitions; disclose accurately.
- [ ] Explain TLS/WSS transport encryption separately from end-to-end encryption.
- [ ] Describe local deletion and volatile relay expiry/restart behavior accurately.

## Build and QA
- [ ] Run flutter test, flutter analyze, Android release build and relay tests.
- [ ] Measure actual APK/AAB download and installed sizes from a clean release build.
- [ ] Test offline mood detection in airplane mode for all 10 supported languages.
- [ ] Test app mute/DND, OS silent/DND behavior, 2-second throttle, quiet hours, per-contact mute, large text and reduced motion.
- [ ] Test encrypted local backup/restore on a second device and verify keys cannot be restored without the backup password.
- [ ] Test Nearby carrier mode on at least two physical Android devices; simulator tests do not prove radio range.

## Asset licensing register
- [ ] Starter manifests contain references/placeholders only; no sound/song/GIF assets are bundled by this change.
- [ ] For every media file, record creator, source, exact license, attribution text and proof of permission.
- [ ] The requested fahhh-style oops/fail clip must be an original recording or explicitly licensed.
- [ ] Bollywood-style and anime-style packs must use original/licensed compositions and recordings, not film/anime soundtrack clips or dialogue.
- [ ] Meme GIF/image backgrounds need a source and license record per file; “found online” is not a license.
