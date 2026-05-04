import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/safe_route.dart';
import '../../providers/route_providers.dart';
import '../../providers/network_providers.dart';

class SafeRoutesScreen extends ConsumerWidget {
  const SafeRoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routeProvider);

    return Scaffold(
      body: routes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_outlined, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  const Text(
                    'NO ROUTE REPORTS YET',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Report safe or blocked routes for others',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final route = routes[index];
                return _RouteCard(route: route);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showReportRouteModal(context, ref),
        backgroundColor: Colors.orangeAccent,
        icon: const Icon(Icons.add_road, color: Colors.white),
        label: const Text('REPORT',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  void _showReportRouteModal(BuildContext context, WidgetRef ref) {
    final fromController = TextEditingController();
    final toController = TextEditingController();
    final descController = TextEditingController();
    RouteStatus selectedStatus = RouteStatus.safe;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.map,
                            color: Colors.orangeAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text('REPORT ROUTE',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: fromController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'From (e.g. "Main Square")',
                      prefixIcon:
                          Icon(Icons.trip_origin, color: Colors.greenAccent, size: 16),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: toController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'To (e.g. "Hospital District")',
                      prefixIcon:
                          Icon(Icons.location_on, color: Colors.redAccent, size: 16),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Notes (e.g. "Checkpoint at bridge")',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  const Text('ROUTE STATUS',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    children: RouteStatus.values.map((status) {
                      final isSelected = selectedStatus == status;
                      final statusColor = Color(status.colorValue);
                      return Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedStatus = status),
                          child: Container(
                            margin: EdgeInsets.only(
                                right:
                                    status != RouteStatus.blocked ? 8 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? statusColor.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? statusColor
                                    : Colors.white.withValues(alpha: 0.1),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  status == RouteStatus.safe
                                      ? Icons.check_circle
                                      : status == RouteStatus.caution
                                          ? Icons.warning
                                          : Icons.block,
                                  color: isSelected
                                      ? statusColor
                                      : Colors.grey,
                                  size: 24,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  status.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? statusColor
                                        : Colors.grey,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (fromController.text.isNotEmpty &&
                            toController.text.isNotEmpty) {
                          ref.read(routeProvider.notifier).addRoute(
                                fromController.text,
                                toController.text,
                                descController.text,
                                selectedStatus,
                              );
                          // Sync immediately
                          final peers = ref
                                  .read(connectedPeersProvider)
                                  .valueOrNull ??
                              [];
                          if (peers.isNotEmpty) {
                            final ips = peers
                                .map((p) => p.ipAddress)
                                .whereType<String>()
                                .toList();
                            ref
                                .read(wifiMeshManagerProvider)
                                .syncRoutes(ref.read(routeProvider), ips);
                          }
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text('BROADCAST ROUTE',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// =============================================================================
// ROUTE CARD
// =============================================================================

class _RouteCard extends StatelessWidget {
  final SafeRoute route;
  const _RouteCard({required this.route});

  @override
  Widget build(BuildContext context) {
    final statusColor = Color(route.status.colorValue);
    final reliability = route.reliability;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Route visualization
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status indicator
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Icon(
                    route.status == RouteStatus.safe
                        ? Icons.check_circle
                        : route.status == RouteStatus.caution
                            ? Icons.warning
                            : Icons.block,
                    color: statusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Route details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // From → To
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              route.from,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.arrow_forward,
                                color: statusColor, size: 16),
                          ),
                          Flexible(
                            child: Text(
                              route.to,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (route.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          route.description,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Reliability bar + metadata
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(11)),
            ),
            child: Column(
              children: [
                // Reliability bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: reliability,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      reliability > 0.5
                          ? Colors.greenAccent
                          : reliability > 0.2
                              ? Colors.orangeAccent
                              : Colors.redAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'RELIABILITY: ${(reliability * 100).toInt()}%',
                      style: TextStyle(
                        color: reliability > 0.5
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${route.timeAgo} • ${route.hopCount} hops',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
