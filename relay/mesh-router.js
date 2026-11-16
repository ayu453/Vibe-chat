const MAX_ENVELOPE_BYTES = 32 * 1024;
const MAX_LIFETIME_MS = 48 * 60 * 60 * 1000;
const MAX_HOPS = 8;
const MAX_COPIES = 6;
const MAX_STORAGE_BYTES = 20 * 1024 * 1024;
const ID_RE = /^[A-Za-z0-9_-]{16,96}$/;

export class MeshRouter {
  constructor({ maxBytes = MAX_STORAGE_BYTES } = {}) {
    this.maxBytes = maxBytes;
    this.items = new Map();
    this.subscribers = new Map();
    this.peerRates = new Map();
    this.bytes = 0;
  }

  cleanup(now) {
    for (const [id, item] of this.items) {
      if (item.expiresAt <= now) {
        this.items.delete(id);
        this.bytes -= item.byteSize;
      }
    }
    for (const [peer, events] of this.peerRates) {
      const live = events.filter(t => t > now - 60_000);
      if (live.length) this.peerRates.set(peer, live);
      else this.peerRates.delete(peer);
    }
  }

  subscribe(ws, tags, now = Date.now()) {
    this.cleanup(now);
    this.unsubscribe(ws);
    if (!Array.isArray(tags) || tags.length > 256) {
      throw new TypeError('Invalid mesh tag list');
    }
    const clean = [...new Set(tags)].filter(tag =>
      typeof tag === 'string' && /^[A-Za-z0-9_-]{16,96}$/.test(tag));
    ws.__vibeMeshTags = clean;
    for (const tag of clean) {
      if (!this.subscribers.has(tag)) this.subscribers.set(tag, new Set());
      this.subscribers.get(tag).add(ws);
    }
    const envelopes = [...this.items.values()]
      .filter(item => clean.includes(item.tag))
      .map(item => item.envelope);
    return { count: clean.length, envelopes };
  }

  unsubscribe(ws) {
    for (const tag of ws.__vibeMeshTags || []) {
      const peers = this.subscribers.get(tag);
      peers?.delete(ws);
      if (peers?.size === 0) this.subscribers.delete(tag);
    }
    ws.__vibeMeshTags = [];
  }

  publish(peerId, envelope, now = Date.now()) {
    this.cleanup(now);
    if (!envelope || typeof envelope !== 'object' || Array.isArray(envelope)) {
      return { accepted: false, duplicate: false, error: 'INVALID_ENVELOPE' };
    }
    const allowed = ['id', 'tag', 'ciphertext', 'createdAt', 'expiresAt', 'hopCount', 'copiesLeft'];
    if (Object.keys(envelope).some(k => !allowed.includes(k)) ||
        allowed.some(k => !Object.hasOwn(envelope, k))) {
      return { accepted: false, duplicate: false, error: 'INVALID_ENVELOPE_FIELDS' };
    }
    const { id, tag, ciphertext, createdAt, expiresAt, hopCount, copiesLeft } = envelope;
    const bytes = Buffer.byteLength(JSON.stringify(envelope), 'utf8');
    if (typeof id !== 'string' || !ID_RE.test(id) ||
        typeof tag !== 'string' || !ID_RE.test(tag) ||
        typeof ciphertext !== 'string' || !ciphertext ||
        bytes > MAX_ENVELOPE_BYTES ||
        !Number.isSafeInteger(createdAt) || !Number.isSafeInteger(expiresAt) ||
        createdAt > now + 300_000 || expiresAt <= now ||
        expiresAt <= createdAt || expiresAt - createdAt > MAX_LIFETIME_MS ||
        !Number.isInteger(hopCount) || hopCount < 0 || hopCount > MAX_HOPS ||
        !Number.isInteger(copiesLeft) || copiesLeft < 0 || copiesLeft > MAX_COPIES) {
      return { accepted: false, duplicate: false, error: 'INVALID_ENVELOPE' };
    }
    const events = this.peerRates.get(peerId) || [];
    if (events.length >= 30) return { accepted: false, duplicate: false, error: 'MESH_RATE_LIMIT' };
    if (this.items.has(id)) return { accepted: false, duplicate: true };
    if (bytes > this.maxBytes) return { accepted: false, duplicate: false, error: 'MESH_STORAGE_FULL' };
    this.peerRates.set(peerId, [...events, now]);
    while (this.bytes + bytes > this.maxBytes) {
      const oldest = this.items.values().next().value;
      if (!oldest) break;
      this.items.delete(oldest.id);
      this.bytes -= oldest.byteSize;
    }
    const safe = Object.freeze({ id, tag, ciphertext, createdAt, expiresAt, hopCount, copiesLeft });
    this.items.set(id, { id, tag, expiresAt, envelope: safe, byteSize: bytes });
    this.bytes += bytes;
    let delivered = 0;
    for (const ws of this.subscribers.get(tag) || []) {
      if (ws.readyState === 1) {
        ws.send(JSON.stringify({ type: 'mesh_envelope', envelope: safe }));
        delivered++;
      }
    }
    return { accepted: true, duplicate: false, delivered };
  }

  inventory() {
    return [...this.items.keys()];
  }
}
