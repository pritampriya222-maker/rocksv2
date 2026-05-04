import 'dart:convert';
import 'dart:io';
import 'package:offline_mesh_app/core/models/news_post.dart';
import 'package:offline_mesh_app/core/models/public_alert.dart';
import 'package:offline_mesh_app/core/models/safe_route.dart';

/// Aggregates multiple data types into a single compressed payload
/// suitable for QR-based "Dead Drop" communal communication points.
class DeadDropBundle {
  static const String magic = 'MESH_DROP_V1';

  final List<PublicAlert> alerts;
  final List<NewsPost> news;
  final List<SafeRoute> routes;
  final DateTime createdAt;

  DeadDropBundle({
    this.alerts = const [],
    this.news = const [],
    this.routes = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get totalItems => alerts.length + news.length + routes.length;

  Map<String, dynamic> toJson() => {
        'magic': magic,
        'ts': createdAt.millisecondsSinceEpoch,
        'a': alerts.map((a) => a.toJson()).toList(),
        'n': news.map((n) => n.toJson()).toList(),
        'r': routes.map((r) => r.toJson()).toList(),
      };

  factory DeadDropBundle.fromJson(Map<String, dynamic> json) {
    return DeadDropBundle(
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
      alerts: (json['a'] as List<dynamic>?)
              ?.map((a) =>
                  PublicAlert.fromJson(Map<String, dynamic>.from(a as Map)))
              .toList() ??
          [],
      news: (json['n'] as List<dynamic>?)
              ?.map((n) =>
                  NewsPost.fromJson(Map<String, dynamic>.from(n as Map)))
              .toList() ??
          [],
      routes: (json['r'] as List<dynamic>?)
              ?.map((r) =>
                  SafeRoute.fromJson(Map<String, dynamic>.from(r as Map)))
              .toList() ??
          [],
    );
  }

  /// Encode to raw JSON string for QR code
  String encode() {
    return jsonEncode(toJson());
  }

  /// Decode from raw JSON string
  static DeadDropBundle decode(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      if (json['magic'] != magic) {
        throw FormatException('Invalid Dead Drop bundle format');
      }
      return DeadDropBundle.fromJson(json);
    } catch (e) {
      // Fallback for older Base64+Gzip format just in case
      try {
        final compressed = base64Decode(data);
        final bytes = GZipCodec().decode(compressed);
        final jsonStr = utf8.decode(bytes);
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return DeadDropBundle.fromJson(json);
      } catch (_) {
        throw FormatException('Failed to decode bundle: $e');
      }
    }
  }
}
