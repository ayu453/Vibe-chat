import '../models/mesh_envelope.dart';
import 'mesh_store.dart';

class MeshSimulationResult {
  const MeshSimulationResult({
    required this.reachedGateway,
    required this.uploadedIds,
    required this.duplicateRejected,
    required this.expiredRejected,
    required this.path,
  });
  final bool reachedGateway;
  final List<String> uploadedIds;
  final bool duplicateRejected;
  final bool expiredRejected;
  final List<String> path;
}

/// Deterministic five-node chain simulator. It models opaque carrier behaviour,
/// not Bluetooth radio discovery or a real network connection.
class MeshSimulator {
  MeshSimulationResult run({
    required MeshEnvelope envelope,
    required int nowMs,
    bool carrierMode = true,
  }) {
    final nodes = List.generate(5, (i) => MeshStore());
    final path = <String>['A'];
    nodes[0].store(envelope, nowMs: nowMs);
    if (carrierMode) {
      for (var i = 0; i < 4; i++) {
        final current = nodes[i].inventory(nowMs: nowMs)
            .where((e) => e.id == envelope.id).firstOrNull;
        if (current == null || !current.canForward) break;
        final split = current.splitForForward();
        nodes[i].replace(split.remainingAtSender, nowMs: nowMs);
        if (nodes[i + 1].store(split.transferred, nowMs: nowMs)) {
          path.add(String.fromCharCode(66 + i));
        }
      }
    }
    final gateway = nodes[4].inventory(nowMs: nowMs);
    final uploaded = gateway.where((e) => e.tag == envelope.tag)
        .map((e) => e.id).toList();
    final duplicateRejected = !nodes[4].store(
      envelope.splitForForward().transferred, nowMs: nowMs,
    );
    final expired = MeshEnvelope(
      id: 'expired-envelope-0001',
      tag: envelope.tag,
      ciphertext: 'opaque',
      createdAt: nowMs - MeshEnvelope.maxLifetimeMs,
      expiresAt: nowMs - 1,
      hopCount: 0,
      copiesLeft: 1,
    );
    var expiredRejected = false;
    try {
      nodes[4].store(expired, nowMs: nowMs);
    } on FormatException {
      expiredRejected = true;
    }
    return MeshSimulationResult(
      reachedGateway: uploaded.contains(envelope.id),
      uploadedIds: uploaded,
      duplicateRejected: duplicateRejected,
      expiredRejected: expiredRejected,
      path: path,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
