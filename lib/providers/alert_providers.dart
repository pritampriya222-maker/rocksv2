import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models/public_alert.dart';
import '../providers/network_providers.dart';

class AlertNotifier extends StateNotifier<List<PublicAlert>> {
  final Box _box = Hive.box<dynamic>('public_broadcasts');

  AlertNotifier() : super([]) {
    _loadFromDisk();
  }

  void _loadFromDisk() {
    final List<dynamic>? raw = _box.get('alerts');
    if (raw != null) {
      state = raw.map((json) => PublicAlert.fromJson(Map<String, dynamic>.from(json))).toList();
    }
  }

  Future<void> _saveToDisk() async {
    await _box.put('alerts', state.map((a) => a.toJson()).toList());
  }

  void addAlert(String text, AlertSeverity severity) {
    final newAlert = PublicAlert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      severity: severity,
      createdAt: DateTime.now(),
    );
    
    if (!state.any((a) => a == newAlert)) {
      state = [newAlert, ...state];
      _saveToDisk();
    }
  }

  void syncFromPeer(List<PublicAlert> incoming) {
    final List<PublicAlert> newState = List.from(state);
    bool changed = false;

    for (final alert in incoming) {
      if (!newState.any((a) => a == alert)) {
        newState.add(alert);
        changed = true;
      }
    }

    if (changed) {
      newState.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = newState;
      _saveToDisk();
    }
  }
  
  Future<void> clearAll() async {
    state = [];
    await _box.delete('alerts');
  }
}

final alertProvider = StateNotifierProvider<AlertNotifier, List<PublicAlert>>((ref) {
  final notifier = AlertNotifier();

  ref.listen(incomingAlertsProvider, (previous, next) {
    if (next.hasValue) {
      notifier.syncFromPeer(next.value!);
    }
  });

  ref.listen(connectedPeersProvider, (previous, next) {
    if (next.hasValue && next.value!.isNotEmpty) {
      final manager = ref.read(wifiMeshManagerProvider);
      final alerts = notifier.state;
      if (alerts.isNotEmpty) {
        final ips = next.value!.map((p) => p.ipAddress).whereType<String>().toList();
        manager.syncAlerts(alerts, ips);
      }
    }
  });

  return notifier;
});
