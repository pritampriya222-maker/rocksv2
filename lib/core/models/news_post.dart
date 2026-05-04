import 'dart:convert';

enum NewsCategory {
  safety('SAFETY', 0xFF4FC3F7, '🛡️'),
  medical('MEDICAL', 0xFFEF5350, '🏥'),
  supplies('SUPPLIES', 0xFF66BB6A, '📦'),
  routes('ROUTES', 0xFFFFA726, '🗺️'),
  general('GENERAL', 0xFFAAAAAA, '📢');

  final String label;
  final int colorValue;
  final String emoji;
  const NewsCategory(this.label, this.colorValue, this.emoji);
}

class NewsPost {
  final String id;
  final String title;
  final String body;
  final NewsCategory category;
  final DateTime createdAt;
  final int ttlMs;
  int hopCount;

  NewsPost({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.ttlMs = 3600000, // 1 hour default
    this.hopCount = 0,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >
      createdAt.millisecondsSinceEpoch + ttlMs;

  Duration get timeRemaining {
    final expiresAt = createdAt.millisecondsSinceEpoch + ttlMs;
    final remaining = expiresAt - DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: remaining > 0 ? remaining : 0);
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  NewsPost withIncrementedHop() => NewsPost(
        id: id,
        title: title,
        body: body,
        category: category,
        createdAt: createdAt,
        ttlMs: ttlMs,
        hopCount: hopCount + 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'cat': category.index,
        'ts': createdAt.millisecondsSinceEpoch,
        'ttl': ttlMs,
        'hop': hopCount,
      };

  factory NewsPost.fromJson(Map<String, dynamic> json) {
    return NewsPost(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      category: NewsCategory.values[json['cat'] as int],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
      ttlMs: json['ttl'] as int? ?? 3600000,
      hopCount: json['hop'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NewsPost &&
      other.id == id;

  @override
  int get hashCode => id.hashCode;
}
