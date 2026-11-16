import { createHash, createPublicKey, randomBytes, verify } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { MeshRouter } from './mesh-router.js';

const PORT = Number(process.env.PORT || 8787);
const MAX_MESSAGE_BYTES = 32 * 1024;
const MAX_QUEUE_PER_USER = 100;
const MAX_TTL_MS = 24 * 60 * 60 * 1000;
const RATE_WINDOW_MS = 60_000;
const RATE_LIMIT = 60;
const DEDUPE_TTL_MS = 24 * 60 * 60 * 1000;
const clients = new Map();
const knownIdentities = new Map();
const offlineQueues = new Map();
const dedupe = new Map();
const publicKeyPrefix = Buffer.from('302a300506032b6570032100', 'hex');
const meshRouter = new MeshRouter();

function suffix(raw) {
  return createHash('sha256').update(raw).digest('hex').slice(0, 4).toUpperCase();
}
function send(ws, value) {
  if (ws.readyState === 1) ws.send(JSON.stringify(value));
}
function deliver(ws, envelope) {
  const sender = knownIdentities.get(envelope.from);
  send(ws, {
    type: 'message',
    envelope,
    senderUsername: sender?.username || null,
    senderSigningPublicKey: sender?.signingPublicKey || null,
    senderEncryptionPublicKey: sender?.encryptionPublicKey || null,
    senderEncryptionKeySignature: sender?.encryptionKeySignature || null
  });
}
function cleanup() {
  const now = Date.now();
  for (const [id, entries] of offlineQueues) {
    const live = entries.filter(item => item.expiresAt > now);
    if (live.length) offlineQueues.set(id, live);
    else offlineQueues.delete(id);
  }
  for (const [id, expiresAt] of dedupe) if (expiresAt <= now) dedupe.delete(id);
}
setInterval(cleanup, 60_000).unref();

const wss = new WebSocketServer({ port: PORT, maxPayload: MAX_MESSAGE_BYTES + 2048 });
wss.on('connection', ws => {
  const challenge = randomBytes(32);
  let authenticated = false;
  let identity = null;
  const rate = [];
  const meshRate = [];
  let meshUploadToken = null;
  const authTimer = setTimeout(() => {
    if (!authenticated) ws.close(4001, 'authentication timeout');
  }, 10_000);
  send(ws, { type: 'challenge', challenge: challenge.toString('base64') });

  ws.on('message', raw => {
    let packet;
    try { packet = JSON.parse(raw.toString()); } catch { ws.close(4002, 'invalid json'); return; }
    if (!authenticated) {
      if (packet.type !== 'auth') { ws.close(4003, 'authentication required'); return; }
      try {
        const username = String(packet.username || '');
        const signingKey = Buffer.from(packet.signingPublicKey || '', 'base64');
        const encryptionKey = Buffer.from(packet.encryptionPublicKey || '', 'base64');
        const signature = Buffer.from(packet.signature || '', 'base64');
        const keySignature = Buffer.from(packet.encryptionKeySignature || '', 'base64');
        if (!/^[A-Za-z0-9_]{3,20}$/.test(username) || signingKey.length !== 32 ||
            encryptionKey.length !== 32 || keySignature.length !== 64) {
          ws.close(4004, 'invalid identity'); return;
        }
        const key = createPublicKey({ key: Buffer.concat([publicKeyPrefix, signingKey]), format: 'der', type: 'spki' });
        const proof = Buffer.concat([challenge, Buffer.from(username, 'utf8'), encryptionKey]);
        const binding = Buffer.from('vibe-chat-x25519-v1|' + username + '|' + encryptionKey.toString('base64'));
        if (!verify(null, proof, key, signature) || !verify(null, binding, key, keySignature)) {
          ws.close(4005, 'identity signature invalid'); return;
        }
        identity = {
          id: username + '#' + suffix(signingKey), username,
          signingPublicKey: signingKey.toString('base64'),
          encryptionPublicKey: encryptionKey.toString('base64'),
          encryptionKeySignature: keySignature.toString('base64'), ws
        };
        const old = clients.get(identity.id);
        if (old && old.ws !== ws) old.ws.close(4006, 'replaced by newer session');
        clients.set(identity.id, identity);
        knownIdentities.set(identity.id, {
          username: identity.username,
          signingPublicKey: identity.signingPublicKey,
          encryptionPublicKey: identity.encryptionPublicKey,
          encryptionKeySignature: identity.encryptionKeySignature
        });
        authenticated = true;
        clearTimeout(authTimer);
        send(ws, { type: 'authenticated', id: identity.id });
        meshUploadToken = randomBytes(24).toString('base64url');
        send(ws, { type: 'mesh_upload_token', token: meshUploadToken });
        const queued = offlineQueues.get(identity.id) || [];
        offlineQueues.delete(identity.id);
        for (const item of queued) {
          if (item.expiresAt > Date.now()) {
            deliver(ws, item.envelope);
            const sender = clients.get(item.envelope.from);
            if (sender) send(sender.ws, { type: 'status', id: item.envelope.id, status: 'delivered' });
          }
        }
      } catch { ws.close(4007, 'authentication failed'); }
      return;
    }

    const now = Date.now();
    while (rate.length && rate[0] <= now - RATE_WINDOW_MS) rate.shift();
    if (rate.length >= RATE_LIMIT) { send(ws, { type: 'error', code: 'RATE_LIMIT' }); return; }
    rate.push(now);

    if (packet.type === 'mesh_subscribe') {
      const tags = Array.isArray(packet.tags) ? packet.tags : [];
      try {
        const result = meshRouter.subscribe(ws, tags, now);
        send(ws, { type: 'mesh_subscribed', count: result.count });
        for (const envelope of result.envelopes) send(ws, { type: 'mesh_envelope', envelope });
      } catch {
        send(ws, { type: 'error', code: 'INVALID_MESH_SUBSCRIPTION' });
      }
      return;
    }
    if (packet.type === 'mesh_publish') {
      while (meshRate.length && meshRate[0] <= now - RATE_WINDOW_MS) meshRate.shift();
      if (!meshUploadToken || packet.token !== meshUploadToken) {
        send(ws, { type: 'error', code: 'MESH_TOKEN_REQUIRED' }); return;
      }
      meshUploadToken = randomBytes(24).toString('base64url');
      send(ws, { type: 'mesh_upload_token', token: meshUploadToken });
      if (meshRate.length >= 30) {
        send(ws, { type: 'error', code: 'MESH_RATE_LIMIT' }); return;
      }
      meshRate.push(now);
      const result = meshRouter.publish(identity.id, packet.envelope, now);
      if (!result.accepted && !result.duplicate) {
        send(ws, { type: 'error', code: result.error }); return;
      }
      send(ws, { type: 'mesh_status', id: packet.envelope?.id, status: result.duplicate ? 'duplicate' : 'stored' });
      return;
    }
    if (packet.type === 'lookup') {
      const peer = knownIdentities.get(String(packet.to || ''));
      send(ws, { type: 'lookup_result', requestId: packet.requestId, found: Boolean(peer), ...(peer || {}) });
      return;
    }
    if (packet.type !== 'message') return;
    const envelope = packet.envelope || {};
    const id = String(envelope.id || '');
    const to = String(envelope.to || '');
    const ciphertext = String(envelope.ciphertext || '');
    const ttl = Math.min(Number(envelope.ttl) || MAX_TTL_MS, MAX_TTL_MS);
    if (!/^[A-Za-z0-9_-]{8,80}$/.test(id) || !to || to.length > 64 ||
        !ciphertext || Buffer.byteLength(ciphertext, 'utf8') > MAX_MESSAGE_BYTES ||
        !Number.isFinite(ttl) || ttl <= 0) {
      send(ws, { type: 'error', code: 'INVALID_ENVELOPE' }); return;
    }
    if (!knownIdentities.has(to)) { send(ws, { type: 'error', code: 'UNKNOWN_RECIPIENT', id }); return; }
    if (dedupe.has(id)) { send(ws, { type: 'status', id, status: 'sent' }); return; }
    dedupe.set(id, now + DEDUPE_TTL_MS);
    const safeEnvelope = { id, to, from: identity.id, ciphertext, ttl };
    const recipient = clients.get(to);
    if (recipient) {
      deliver(recipient.ws, safeEnvelope);
      send(ws, { type: 'status', id, status: 'sent' });
      send(ws, { type: 'status', id, status: 'delivered' });
      return;
    }
    const queue = offlineQueues.get(to) || [];
    if (queue.length >= MAX_QUEUE_PER_USER) {
      dedupe.delete(id);
      send(ws, { type: 'error', code: 'RECIPIENT_QUEUE_FULL', id });
      return;
    }
    queue.push({ envelope: safeEnvelope, expiresAt: now + ttl });
    offlineQueues.set(to, queue);
    send(ws, { type: 'status', id, status: 'sent' });
  });

  ws.on('close', () => {
    clearTimeout(authTimer);
    meshRouter.unsubscribe(ws);
    if (identity && clients.get(identity.id)?.ws === ws) clients.delete(identity.id);
  });
  ws.on('error', () => {});
});
wss.on('listening', () => process.stdout.write('Vibe Chat RAM relay listening on ' + PORT + '\\n'));
