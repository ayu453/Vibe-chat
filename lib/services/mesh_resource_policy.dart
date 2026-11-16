/// Resource guard for peer exchanges and device power policy.
class MeshResourcePolicy {
  MeshResourcePolicy({
    this.maxEnvelopesPerPeerPerMinute = 30,
    this.maxEnvelopeBytes = 32 * 1024,
  });
  final int maxEnvelopesPerPeerPerMinute;
  final int maxEnvelopeBytes;
  final Map<String, List<int>> _peerEvents = {};

  bool allowPeerEnvelope(String peerId, int nowMs, int byteLength) {
    if (byteLength <= 0 || byteLength > maxEnvelopeBytes) return false;
    final events = _peerEvents.putIfAbsent(peerId, () => <int>[]);
    events.removeWhere((time) => time <= nowMs - 60000);
    if (events.length >= maxEnvelopesPerPeerPerMinute) return false;
    events.add(nowMs);
    return true;
  }

  bool shouldPauseForBattery({
    required int batteryPercent,
    required bool isCharging,
    required bool carryOnlyWhileCharging,
    int pauseBelowPercent = 15,
  }) {
    if (batteryPercent < pauseBelowPercent) return true;
    return carryOnlyWhileCharging && !isCharging;
  }
}
