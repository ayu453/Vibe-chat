import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/mesh_envelope.dart';
import 'mesh_resource_policy.dart';
import 'sqlite_mesh_outbox.dart';

/// Android Nearby Connections adapter. It transports opaque envelopes only;
/// the application message payload remains end-to-end encrypted.
class NearbyMeshTransport {
  NearbyMeshTransport({SqliteMeshOutbox? outbox})
      : _outbox = outbox ?? SqliteMeshOutbox();

  static const String _serviceId = 'app.vibechat.mesh.v1';
  static const String _displayName = 'Vibe relay node';
  final Nearby _nearby = Nearby();
  final SqliteMeshOutbox _outbox;
  final MeshResourcePolicy _policy = MeshResourcePolicy();
  final Set<String> _endpoints = {};
  final Set<String> _inFlight = {};
  bool _running = false;
  bool _disposed = false;

  bool get isRunning => _running;
  int get connectedPeers => _endpoints.length;

  Future<bool> start({
    bool carryOnlyWhileCharging = false,
    required int batteryPercent,
    required bool isCharging,
  }) async {
    if (_disposed) throw StateError('Nearby mesh transport is disposed');
    if (_policy.shouldPauseForBattery(
      batteryPercent: batteryPercent,
      isCharging: isCharging,
      carryOnlyWhileCharging: carryOnlyWhileCharging,
    )) return false;
    if (_running) return true;

    final permissions = await <Permission>[
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();
    if (permissions.values.any((status) => !status.isGranted)) {
      throw StateError('Nearby permissions were not granted');
    }

    final advertising = await _nearby.startAdvertising(
      _displayName,
      Strategy.P2P_CLUSTER,
      serviceId: _serviceId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
    final discovery = await _nearby.startDiscovery(
      _displayName,
      Strategy.P2P_CLUSTER,
      serviceId: _serviceId,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: (id) {
        if (id != null) _endpoints.remove(id);
      },
    );
    _running = advertising && discovery;
    if (!_running) {
      await stop();
      throw StateError('Nearby advertising or discovery could not start');
    }
    return true;
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    // Carriers are anonymous and only receive opaque, bounded envelopes.
    unawaited(_nearby.acceptConnection(id, onPayLoadRecieved: _onPayloadReceived));
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      _endpoints.add(id);
      unawaited(_sendInventory(id));
    } else {
      _endpoints.remove(id);
    }
  }

  void _onDisconnected(String id) => _endpoints.remove(id);

  void _onEndpointFound(String id, String name, String serviceId) {
    if (_disposed || _endpoints.contains(id)) return;
    unawaited(_nearby.requestConnection(
      _displayName,
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    ));
  }

  Future<void> _sendPacket(String endpointId, Map<String, Object?> packet) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(packet)));
    if (bytes.length > MeshEnvelope.maxBytes) {
      throw const FormatException('Nearby packet exceeds 32 KB');
    }
    await _nearby.sendBytesPayload(endpointId, bytes);
  }

  Future<void> _sendInventory(String endpointId) async {
    final all = await _outbox.all();
    final ids = all.map((e) => e.id).toList();
    const chunkSize = 128;
    if (ids.isEmpty) {
      await _sendPacket(endpointId, {'type': 'inventory', 'ids': <String>[]});
      return;
    }
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
      await _sendPacket(endpointId, {'type': 'inventory', 'ids': ids.sublist(i, end)});
    }
  }

  Future<void> _onPayloadReceived(String endpointId, Payload payload) async {
    final bytes = payload.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > MeshEnvelope.maxBytes) return;
    if (!_policy.allowPeerEnvelope(endpointId, DateTime.now().millisecondsSinceEpoch, bytes.length)) return;
    try {
      final packet = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (packet['type'] == 'inventory') {
        final ids = (packet['ids'] as List<dynamic>? ?? const [])
            .whereType<String>().toSet();
        final local = await _outbox.all();
        for (final envelope in local) {
          if (ids.contains(envelope.id) || !envelope.canForward) continue;
          if (!_inFlight.add(envelope.id)) continue;
          try {
            final split = envelope.splitForForward();
            await _sendPacket(endpointId, {
              'type': 'envelope',
              'envelope': split.transferred.toJson(),
            });
            await _outbox.replace(split.remainingAtSender);
          } finally {
            _inFlight.remove(envelope.id);
          }
        }
      } else if (packet['type'] == 'envelope') {
        final envelope = MeshEnvelope.fromJson(
          packet['envelope'] as Map<String, dynamic>);
        await _outbox.store(envelope);
      }
    } catch (_) {
      // Invalid peer packets are dropped without exposing local identity/data.
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _nearby.stopDiscovery();
    await _nearby.stopAdvertising();
    await _nearby.stopAllEndpoints();
    _endpoints.clear();
    _inFlight.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _outbox.close();
  }
}
