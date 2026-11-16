import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createHash, generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import WebSocket from 'ws';
const url = process.env.RELAY_URL || 'ws://127.0.0.1:8787';
const suffix = key => createHash('sha256').update(key).digest('hex').slice(0, 4).toUpperCase();
function client(username) {
  const signing = generateKeyPairSync('ed25519');
  const encryption = generateKeyPairSync('x25519');
  const signingRaw = signing.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
  const encryptionRaw = encryption.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
  const encryptionKeySignature = sign(null,
    Buffer.from('vibe-chat-x25519-v1|' + username + '|' + encryptionRaw.toString('base64')),
    signing.privateKey);
  return { username, id: username + '#' + suffix(signingRaw), signing, signingRaw, encryptionRaw, encryptionKeySignature };
}
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
async function connect(identity) {
  const ws = new WebSocket(url);
  const challengePromise = nextPacket(ws, p => p.type === 'challenge');
  await once(ws, 'open');
  const challengePacket = await challengePromise;
  const challenge = Buffer.from(challengePacket.challenge, 'base64');
  const proof = Buffer.concat([challenge, Buffer.from(identity.username), identity.encryptionRaw]);
  const signature = sign(null, proof, identity.signing.privateKey);
  const authPromise = nextPacket(ws, p => p.type === 'authenticated');
  ws.send(JSON.stringify({
    type: 'auth', username: identity.username,
    signingPublicKey: identity.signingRaw.toString('base64'),
    encryptionPublicKey: identity.encryptionRaw.toString('base64'),
    signature: signature.toString('base64'),
    encryptionKeySignature: identity.encryptionKeySignature.toString('base64')
  }));
  const auth = await authPromise;
  assert.equal(auth.id, identity.id);
  return ws;
}
const alice = client('alice');
const bob = client('bob');
const aliceWs = await connect(alice);
const bobWs = await connect(bob);
const delivered = nextPacket(bobWs, p => p.type === 'message');
const deliveredStatus = nextPacket(aliceWs, p => p.type === 'status' && p.status === 'delivered');
const envelope = {
  id: randomBytes(16).toString('hex'), to: bob.id, from: alice.id,
  ciphertext: Buffer.from('opaque-encrypted-test-payload').toString('base64'), ttl: 60000
};
aliceWs.send(JSON.stringify({ type: 'message', envelope }));
const received = await delivered;
assert.equal(received.envelope.id, envelope.id);
assert.equal(received.envelope.from, alice.id);
assert.equal(received.envelope.to, bob.id);
assert.equal(received.envelope.ciphertext, envelope.ciphertext);
assert.equal(received.senderEncryptionPublicKey, alice.encryptionRaw.toString('base64'));
assert.equal(received.senderEncryptionKeySignature, alice.encryptionKeySignature.toString('base64'));
assert.equal((await deliveredStatus).status, 'delivered');
aliceWs.close(); bobWs.close();
console.log('PASS: two authenticated fake clients exchanged an opaque envelope.');
