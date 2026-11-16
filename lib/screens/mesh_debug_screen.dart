import 'package:flutter/material.dart';
import '../models/mesh_envelope.dart';
import '../services/mesh_simulator.dart';

class MeshDebugScreen extends StatefulWidget {
  const MeshDebugScreen({super.key});
  @override
  State<MeshDebugScreen> createState() => _MeshDebugScreenState();
}

class _MeshDebugScreenState extends State<MeshDebugScreen> {
  MeshSimulationResult? _result;

  void _runSimulation() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final packet = MeshEnvelope(
      id: 'debug_${now}_envelope',
      tag: 'debug_recipient_route_tag',
      ciphertext: 'opaque-demo-ciphertext',
      createdAt: now,
      expiresAt: now + const Duration(hours: 1).inMilliseconds,
      hopCount: 0,
      copiesLeft: MeshEnvelope.maxCopies,
    );
    setState(() => _result = MeshSimulator().run(envelope: packet, nowMs: now));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mesh debug')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Store-and-forward test', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('This deterministic simulation moves one opaque envelope through five nodes. It does not scan for nearby phones or prove Bluetooth delivery.'),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _runSimulation,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Run A → B → C → D → E test'),
      ),
      if (_result != null) ...[
        const SizedBox(height: 20),
        _resultRow('Path', _result!.path.join(' → ')),
        _resultRow('Reached internet gateway', _result!.reachedGateway ? 'Yes' : 'No'),
        _resultRow('Uploaded envelope IDs', _result!.uploadedIds.length.toString()),
        _resultRow('Duplicate rejected', _result!.duplicateRejected ? 'Yes' : 'No'),
        _resultRow('Expired packet rejected', _result!.expiredRejected ? 'Yes' : 'No'),
      ],
      const Divider(height: 36),
      Text('Protocol limits', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const ListTile(dense: true, title: Text('Envelope size'), trailing: Text('32 KB max')),
      const ListTile(dense: true, title: Text('Carrier storage'), trailing: Text('20 MB max')),
      const ListTile(dense: true, title: Text('Envelope lifetime'), trailing: Text('48 hours max')),
      const ListTile(dense: true, title: Text('Forwarding'), trailing: Text('8 hops / 6 copies')),
      const ListTile(dense: true, title: Text('Relay storage'), trailing: Text('RAM only')),
      const SizedBox(height: 8),
      const Text('Real nearby radio transport, background execution, battery controls and device-to-device testing are not connected yet.',
        style: TextStyle(color: Colors.deepOrange)),
    ]),
  );

  Widget _resultRow(String label, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}
