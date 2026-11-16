import '../models/mesh_envelope.dart';

/// Bounded opaque carrier store. The caller persists this interface locally;
/// this in-memory implementation is also used by the deterministic simulator.
class MeshStore {
  MeshStore({this.maxBytes = 20 * 1024 * 1024});
  final int maxBytes;
  final Map<String, MeshEnvelope> _items = {};

  int get length => _items.length;
  int get usedBytes => _items.values.fold<int>(0, (n, e) => n + e.encode().length);

  bool contains(String id) => _items.containsKey(id);

  void pruneExpired(int nowMs) {
    _items.removeWhere((_, e) => e.isExpiredAt(nowMs));
  }

  /// Returns false for duplicates, expired packets, or packets that cannot fit.
  bool store(MeshEnvelope envelope, {required int nowMs}) {
    envelope.validate(nowMs: nowMs);
    pruneExpired(nowMs);
    if (contains(envelope.id)) return false;
    final size = envelope.encode().length;
    if (size > maxBytes) return false;
    while (_items.isNotEmpty && usedBytes + size > maxBytes) {
      final oldest = _items.values.reduce(
        (a, b) => a.createdAt <= b.createdAt ? a : b,
      );
      _items.remove(oldest.id);
    }
    _items[envelope.id] = envelope;
    return true;
  }

  List<MeshEnvelope> inventory({required int nowMs}) {
    pruneExpired(nowMs);
    return List.unmodifiable(_items.values);
  }

  void replace(MeshEnvelope envelope, {required int nowMs}) {
    envelope.validate(nowMs: nowMs);
    if (_items.containsKey(envelope.id)) _items[envelope.id] = envelope;
  }

  void remove(String id) => _items.remove(id);
}
