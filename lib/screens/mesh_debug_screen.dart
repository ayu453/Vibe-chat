import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mesh_envelope.dart';
import '../services/mesh_simulator.dart';
import '../services/nearby_mesh_transport.dart';

class MeshDebugScreen extends StatefulWidget {
  const MeshDebugScreen({super.key, required this.transport});
  final NearbyMeshTransport transport;
  @override
  State<MeshDebugScreen> createState() => _MeshDebugScreenState();
}

class _MeshDebugScreenState extends State<MeshDebugScreen> {
  final Battery _battery = Battery();
  MeshSimulationResult? _result;
  bool _carrierEnabled = true;
  bool _carryOnlyWhileCharging = false;
  bool _carrierRunning = false;
  bool _starting = false;
  String? _carrierMessage;
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _powerTimer;

  @override
  void initState() {
    super.initState();
    _batterySubscription = _battery.onBatteryStateChanged.listen((_) {
      unawaited(_syncCarrier());
    });
    _powerTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_syncCarrier());
    });
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _carrierEnabled = prefs.getBool('mesh_carrier_enabled') ?? true;
      _carryOnlyWhileCharging = prefs.getBool('mesh_carry_only_charging') ?? false;
    });
    if (_carrierEnabled) await _syncCarrier();
  }

  Future<void> _syncCarrier() async {
    if (!mounted || _starting) return;
    if (!_carrierEnabled) {
      await widget.transport.stop();
      if (mounted) setState(() { _carrierRunning = false; _carrierMessage = 'Carrier mode is off'; });
      return;
    }
    setState(() { _starting = true; _carrierMessage = null; });
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final charging = state == BatteryState.charging || state == BatteryState.full;
      if (level < 15 || (_carryOnlyWhileCharging && !charging)) {
        await widget.transport.stop();
        if (mounted) setState(() {
          _carrierRunning = false;
          _carrierMessage = level < 15
              ? 'Paused: battery below 15%'
              : 'Paused: waiting for charging';
        });
      } else {
        final started = await widget.transport.start(
          batteryPercent: level,
          isCharging: charging,
          carryOnlyWhileCharging: _carryOnlyWhileCharging,
        );
        if (mounted) setState(() {
          _carrierRunning = started;
          _carrierMessage = started ? 'Nearby carrier mode is active' : 'Carrier mode paused by power policy';
        });
      }
    } catch (error) {
      if (mounted) setState(() {
        _carrierRunning = false;
        _carrierMessage = 'Could not start nearby mode: $error';
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _setCarrierEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mesh_carrier_enabled', value);
    if (!mounted) return;
    setState(() => _carrierEnabled = value);
    await _syncCarrier();
  }

  Future<void> _setChargingOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mesh_carry_only_charging', value);
    if (!mounted) return;
    setState(() => _carryOnlyWhileCharging = value);
    await _syncCarrier();
  }

  void _runSimulation() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final packet = MeshEnvelope(
      id: 'debug_${now}_envelope',
      tag: 'debug_recipient_route_tag',
      ciphertext: 'opaque-demo-ciphertext',
      createdAt: now,
      expiresAt: now + 3600000,
      hopCount: 0,
      copiesLeft: MeshEnvelope.maxCopies,
    );
    setState(() => _result = MeshSimulator().run(envelope: packet, nowMs: now));
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    _powerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mesh debug')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Nearby carrier mode', style: Theme.of(context).textTheme.titleLarge),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Allow this phone to carry messages'),
        subtitle: const Text('Other Vibe Chat devices may exchange opaque encrypted packets with this phone'),
        value: _carrierEnabled,
        onChanged: _starting ? null : _setCarrierEnabled,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Carry only while charging'),
        value: _carryOnlyWhileCharging,
        onChanged: !_carrierEnabled || _starting ? null : _setChargingOnly,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Carrier status'),
        subtitle: Text(_carrierMessage ?? 'Checking device status…'),
        trailing: _starting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(_carrierRunning ? Icons.wifi_tethering : Icons.pause_circle_outline,
                color: _carrierRunning ? Colors.green : null),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Connected nearby peers'),
        trailing: Text(widget.transport.connectedPeers.toString()),
      ),
      const Text('Nearby Connections requires Android runtime permissions and Location services enabled. This transport currently targets Android; iOS is not supported by this plugin.'),
      const Divider(height: 36),
      Text('Store-and-forward test', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('This deterministic simulation moves one opaque envelope through five nodes. It does not scan for nearby phones or prove radio delivery.'),
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
        _resultRow('Reached relay', _result!.reachedRelay ? 'Yes' : 'No'),
        _resultRow('Reached recipient tag', _result!.reachedRecipient ? 'Yes' : 'No'),
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
    ]),
  );

  Widget _resultRow(String label, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}
