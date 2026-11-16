# Vibe Chat RAM relay

Node.js WebSocket relay. No database, message-content logs, or disk queue. Active sessions, public-key directory, dedupe IDs and encrypted offline envelopes exist in RAM only. Queues expire within 24 hours and vanish on restart.

## Local run
`cd relay && npm install && npm start`
In another terminal: `cd relay && npm run test:two-clients`

## Render deployment
Create a Web Service from this repository; set Root Directory to `relay`, Build Command to `npm install`, Start Command to `npm start`. Render supplies `PORT`. Use its TLS/WSS endpoint in the app. Fly.io can run the same Node service with TLS.

## Limits and protocol
- Ed25519 signed random challenge authenticates a username and signing public key.
- Route ID is username plus first four uppercase SHA-256 hex characters of the signing public key.
- X25519 public key is directory metadata; messages use XChaCha20-Poly1305 ciphertext.
- 32 KiB ciphertext max; 100 queued per user; max TTL 24 hours; 60 messages/minute/connection; message ID dedupe 24 hours.
- Relay sees sender/recipient IDs, timing and ciphertext size, but not message text, mood or sound ID.
- Recipient must have connected to the same running relay at least once so its public encryption key is known. The RAM directory resets at restart.
- Four-character suffixes can collide. Production should use a longer fingerprint and key verification.
