import 'dart:convert';

enum RouteStatus {
  safe('SAFE', 0xFF66BB6A),
  caution('CAUTION', 0xFFFFA726),
  blocked('BLOCKED', 0xFFEF5350);

  final String label;
  final int colorValue;
  const RouteStatus(this.label, this.colorValue);
}

class SafeRoute {
  final String id;
  final String from;
  final String to;
  final String description;
  final RouteStatus status;
  final DateTime reportedAt;
  final int ttlMs;
  int hopCount;

  SafeRoute({
    required this.id,
    required this.from,
    required this.to,
    required this.description,
    required this.status,
    required this.reportedAt,
    this.ttlMs = 1800000, // 30 min default — routes go stale fast
    this.hopCount = 0,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >
      reportedAt.millisecondsSinceEpoch + ttlMs;

  String get timeAgo {
    final diff = DateTime.now().difference(reportedAt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  /// Reliability fades over time (1.0 = just reported, 0.0 = about to expire)
  double get reliability {
    final elapsed = DateTime.now().millisecondsSinceEpoch -
        reportedAt.millisecondsSinceEpoch;
    final ratio = 1.0 - (elapsed / ttlMs).clamp(0.0, 1.0);
    return ratio;
  }

  SafeRoute withIncrementedHop() => SafeRoute(
        id: id,
        from: from,
        to: to,
        description: description,
        status: status,
        reportedAt: reportedAt,
        ttlMs: ttlMs,
        hopCount: hopCount + 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'desc': description,
        'st': status.index,
        'ts': reportedAt.millisecondsSinceEpoch,
        'ttl': ttlMs,
        'hop': hopCount,
      };

  factory SafeRoute.fromJson(Map<String, dynamic> json) {
    return SafeRoute(
      id: json['id'] as String,
      from: json['from'] as String,
      to: json['to'] as String,
      description: json['desc'] as String,
      status: RouteStatus.values[json['st'] as int],
      reportedAt: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
      ttlMs: json['ttl'] as int? ?? 1800000,
      hopCount: json['hop'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) => other is SafeRoute && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
