import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createHash, generateKeyPairSync, sign } from 'node:crypto';
import WebSocket from 'ws';

const url = process.env.RELAY_URL || 'ws://127.0.0.1:8787';
const suffix = key => createHash('sha256').update(key).digest('hex').slice(0, 4).toUpperCase();

function nextPacket(ws, predicate, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { cleanup(); reject(new Error('packet timeout')); }, timeout);
    const onMessage = raw => {
      const packet = JSON.parse(raw.toString());
      if (predicate(packet)) { cleanup(); resolve(packet); }
    };
    const cleanup = () => { clearTimeout(timer); ws.off('message', onMessage); };
    ws.on('message', onMessage);
  });
}

function makeIdentity(username) {
  const signing = generateKeyPairSync('ed25519');
  const encryption = generateKeyPairSync('x25519');
  const signingRaw = signing.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
  const encryptionRaw = encryption.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
  const encryptionKeySignature = sign(null,
    Buffer.from('vibe-chat-x25519-v1|' + username + '|' + encryptionRaw.toString('base64')),
    signing.privateKey);
  return {
    username, id: username + '#' + suffix(signingRaw), signing,
    signingRaw, encryptionRaw, encryptionKeySignature
  };
}

async function connect(identity) {
  const ws = new WebSocket(url);
  const challengePromise = nextPacket(ws, p => p.type === 'challenge');
  await once(ws, 'open');
  const challenge = Buffer.from((await challengePromise).challenge, 'base64');
  const proof = Buffer.concat([challenge, Buffer.from(identity.username), identity.encryptionRaw]);
  const signature = sign(null, proof, identity.signing.privateKey);
  const authPromise = nextPacket(ws, p => p.type === 'authenticated');
  const tokenPromise = nextPacket(ws, p => p.type === 'mesh_upload_token');
  ws.send(JSON.stringify({
    type: 'auth', username: identity.username,
    signingPublicKey: identity.signingRaw.toString('base64'),
    encryptionPublicKey: identity.encryptionRaw.toString('base64'),
    signature: signature.toString('base64'),
    encryptionKeySignature: identity.encryptionKeySignature.toString('base64')
  }));
  const auth = await authPromise;
  assert.equal(auth.id, identity.id);
  const token = (await tokenPromise).token;
  return { ws, token };
}

const recipient = await connect(makeIdentity('meshRecipient'));
const gateway = await connect(makeIdentity('meshGateway'));
const tag = 'pairwise_directional_tag_01';
const subscribed = nextPacket(recipient.ws, p => p.type === 'mesh_subscribed');
recipient.ws.send(JSON.stringify({ type: 'mesh_subscribe', tags: [tag] }));
assert.equal((await subscribed).count, 1);

const now = Date.now();
const envelope = {
  id: 'mesh_envelope_identifier_001',
  tag,
  ciphertext: 'opaque-encrypted-payload',
  createdAt: now,
  expiresAt: now + 60_000,
  hopCount: 4,
  copiesLeft: 2
};
const delivery = nextPacket(recipient.ws, p => p.type === 'mesh_envelope');
const refreshedToken = nextPacket(gateway.ws, p => p.type === 'mesh_upload_token');
gateway.ws.send(JSON.stringify({
  type: 'mesh_publish', token: gateway.token, envelope
}));
const delivered = await delivery;
assert.equal(delivered.envelope.id, envelope.id);
assert.equal(delivered.envelope.tag, tag);
assert.equal('from' in delivered.envelope, false);
assert.equal('to' in delivered.envelope, false);
const nextToken = (await refreshedToken).token;
const stored = await nextPacket(gateway.ws, p => p.type === 'mesh_status');
assert.equal(stored.status, 'stored');

const duplicateToken = nextPacket(gateway.ws, p => p.type === 'mesh_upload_token');
const duplicateStatus = nextPacket(gateway.ws, p => p.type === 'mesh_status');
gateway.ws.send(JSON.stringify({
  type: 'mesh_publish', token: nextToken, envelope
}));
await duplicateToken;
assert.equal((await duplicateStatus).status, 'duplicate');

const invalidToken = nextPacket(gateway.ws, p => p.type === 'mesh_upload_token');
const invalidPacket = nextPacket(gateway.ws, p => p.type === 'error');
gateway.ws.send(JSON.stringify({
  type: 'mesh_publish',
  token: (await nextPacket(gateway.ws, p => p.type === 'mesh_upload_token')).token,
  envelope: { ...envelope, id: 'mesh_expired_envelope_001', expiresAt: Date.now() - 1 }
}));
await invalidToken;
assert.equal((await invalidPacket).code, 'INVALID_ENVELOPE');

recipient.ws.close();
gateway.ws.close();
console.log('PASS: authenticated tag subscription, opaque relay delivery, upload token, dedupe and expiry.');
