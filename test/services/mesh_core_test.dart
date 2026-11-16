import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_chat/models/mesh_envelope.dart';
import 'package:vibe_chat/services/mesh_simulator.dart';
import 'package:vibe_chat/services/mesh_store.dart';
import 'package:vibe_chat/services/route_tag_service.dart';

void main() {
  const now = 1800000000000;
  MeshEnvelope packet() => const MeshEnvelope(
    id: 'envelope_identifier_0001',
    tag: 'recipient_route_tag_01',
    ciphertext: 'opaque-ciphertext',
    createdAt: now - 1000,
    expiresAt: now + 3600000,
    hopCount: 0,
    copiesLeft: 6,
  );

  test('five-node chain carries opaque envelope to internet gateway', () {
    final result = MeshSimulator().run(envelope: packet(), nowMs: now);
    expect(result.path, ['A', 'B', 'C', 'D', 'E']);
    expect(result.reachedGateway, isTrue);
    expect(result.uploadedIds, [packet().id]);
  });

  test('store deduplicates and evicts oldest first under byte limit', () {
    final store = MeshStore(maxBytes: 350);
    expect(store.store(packet(), nowMs: now), isTrue);
    expect(store.store(packet(), nowMs: now), isFalse);
    final newer = MeshEnvelope(
      id: 'envelope_identifier_0002', tag: packet().tag,
      ciphertext: List.filled(80, 'x').join(), createdAt: now, expiresAt: now + 100000,
      hopCount: 0, copiesLeft: 1);
    store.store(newer, nowMs: now);
    expect(store.contains(newer.id), isTrue);
    expect(store.contains(packet().id), isFalse);
  });

  test('expired packets are rejected', () {
    final expired = MeshEnvelope(
      id: 'expired_envelope_identifier', tag: packet().tag,
      ciphertext: 'opaque', createdAt: now - 10000,
      expiresAt: now - 1, hopCount: 0, copiesLeft: 1);
    expect(() => MeshStore().store(expired, nowMs: now), throwsFormatException);
  });

  test('route tags rotate daily and include yesterday during overlap', () {
    const tags = RouteTagService([1, 2, 3, 4, 5, 6]);
    final day = DateTime.utc(2026, 11, 16);
    expect(tags.tagForDay(day), isNot(tags.tagForDay(day.add(const Duration(days: 1)))));
    expect(tags.subscriptionTags(day), [tags.tagForDay(day), tags.tagForDay(day.subtract(const Duration(days: 1)))]);
  });

  test('same shared secret yields same tag; different contact secret does not', () {
    final a = RouteTagService(List<int>.filled(32, 7));
    final b = RouteTagService(List<int>.filled(32, 7));
    final other = RouteTagService(List<int>.filled(32, 8));
    final day = DateTime.utc(2026, 11, 16);
    expect(a.tagForDay(day), b.tagForDay(day));
    expect(a.tagForDay(day), isNot(other.tagForDay(day)));
  });
}
