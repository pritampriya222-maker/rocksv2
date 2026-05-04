import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models/safe_route.dart';
import 'network_providers.dart';

class RouteNotifier extends StateNotifier<List<SafeRoute>> {
  final Box _box = Hive.box<dynamic>('safe_routes');
  Timer? _expiryTimer;

  RouteNotifier() : super([]) {
    _loadFromDisk();
    _scheduleExpiryCheck();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _loadFromDisk() {
    final raw = _box.get('routes') as List<dynamic>?;
    if (raw != null) {
      state = raw
          .map((json) =>
              SafeRoute.fromJson(Map<String, dynamic>.from(json as Map)))
          .where((r) => !r.isExpired)
          .toList();
    }
  }

  Future<void> _saveToDisk() async {
    await _box.put('routes', state.map((r) => r.toJson()).toList());
  }

  void _scheduleExpiryCheck() {
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final before = state.length;
      state = state.where((r) => !r.isExpired).toList();
      if (state.length != before) _saveToDisk();
    });
  }

  void addRoute(String from, String to, String description, RouteStatus status) {
    final route = SafeRoute(
      id: '${DateTime.now().millisecondsSinceEpoch}_${from.hashCode}',
      from: from,
      to: to,
      description: description,
      status: status,
      reportedAt: DateTime.now(),
    );

    if (!state.any((r) => r.id == route.id)) {
      state = [route, ...state];
      _saveToDisk();
    }
  }

  void syncFromPeer(List<SafeRoute> incoming) {
    final List<SafeRoute> newState = List.from(state);
    bool changed = false;

    for (final route in incoming) {
      if (route.isExpired) continue;
      if (!newState.any((r) => r.id == route.id)) {
        newState.add(route);
        changed = true;
      }
    }

    if (changed) {
      newState.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      state = newState;
      _saveToDisk();
    }
  }

  Future<void> clearAll() async {
    state = [];
    await _box.delete('routes');
  }
}

final routeProvider = StateNotifierProvider<RouteNotifier, List<SafeRoute>>((ref) {
  final notifier = RouteNotifier();

  // 1. Listen for incoming routes from mesh
  ref.listen(incomingRoutesProvider, (previous, next) {
    if (next.hasValue) {
      notifier.syncFromPeer(next.value!);
    }
  });

  // 2. Listen for STATE changes (new local routes) and PUSH immediately
  ref.listenSelf((previous, next) {
    final peers = ref.read(connectedPeersProvider).valueOrNull;
    if (peers != null && peers.isNotEmpty && next.isNotEmpty) {
      final manager = ref.read(wifiMeshManagerProvider);
      final ips = peers.map((p) => p.ipAddress).whereType<String>().toList();
      manager.syncRoutes(next, ips);
    }
  });

  // 3. Auto-sync routes with mesh peers when new peers connect
  ref.listen(connectedPeersProvider, (previous, next) {
    if (next.hasValue && next.value!.isNotEmpty) {
      final manager = ref.read(wifiMeshManagerProvider);
      final routes = notifier.state;
      if (routes.isNotEmpty) {
        final ips = next.value!
            .map((p) => p.ipAddress)
            .whereType<String>()
            .toList();
        manager.syncRoutes(routes, ips);
      }
    }
  });

  return notifier;
});
