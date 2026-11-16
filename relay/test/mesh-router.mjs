import assert from 'node:assert/strict';
import { MeshRouter } from '../mesh-router.js';

const now = 1800000000000;
const packet = {
  id: 'envelope_identifier_0001',
  tag: 'recipient_route_tag_01',
  ciphertext: 'opaque-ciphertext',
  createdAt: now - 1000,
  expiresAt: now + 3600000,
  hopCount: 4,
  copiesLeft: 2
};
const router = new MeshRouter();
const recipient = {
  readyState: 1, packets: [],
  send(raw) { this.packets.push(JSON.parse(raw)); }
};
const subscribed = router.subscribe(recipient, [packet.tag], now);
assert.equal(subscribed.count, 1);
const uploaded = router.publish('gateway-E', packet, now);
assert.equal(uploaded.accepted, true);
assert.equal(recipient.packets[0].envelope.id, packet.id);
assert.equal('from' in recipient.packets[0].envelope, false);
assert.equal('to' in recipient.packets[0].envelope, false);
assert.equal(router.publish('gateway-E', packet, now).duplicate, true);
assert.equal(router.publish('gateway-E', { ...packet, expiresAt: now - 1 }, now).error, 'INVALID_ENVELOPE');
router.cleanup(now + 3600001);
assert.deepEqual(router.inventory(), []);
console.log('PASS: opaque tag routing, dedupe, and expiry.');
