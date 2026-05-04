import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models/news_post.dart';
import 'network_providers.dart';

class NewsNotifier extends StateNotifier<List<NewsPost>> {
  final Box _box = Hive.box<dynamic>('local_news');
  Timer? _expiryTimer;

  NewsNotifier() : super([]) {
    _loadFromDisk();
    _scheduleExpiryCheck();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _loadFromDisk() {
    final raw = _box.get('news') as List<dynamic>?;
    if (raw != null) {
      state = raw
          .map((json) =>
              NewsPost.fromJson(Map<String, dynamic>.from(json as Map)))
          .where((p) => !p.isExpired)
          .toList();
    }
  }

  Future<void> _saveToDisk() async {
    await _box.put('news', state.map((n) => n.toJson()).toList());
  }

  void _scheduleExpiryCheck() {
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final before = state.length;
      state = state.where((p) => !p.isExpired).toList();
      if (state.length != before) _saveToDisk();
    });
  }

  void addPost(String title, String body, NewsCategory category) {
    final post = NewsPost(
      id: '${DateTime.now().millisecondsSinceEpoch}_${title.hashCode}',
      title: title,
      body: body,
      category: category,
      createdAt: DateTime.now(),
    );

    if (!state.any((n) => n.id == post.id)) {
      state = [post, ...state];
      _saveToDisk();
    }
  }

  void syncFromPeer(List<NewsPost> incoming) {
    final List<NewsPost> newState = List.from(state);
    bool changed = false;

    for (final post in incoming) {
      if (post.isExpired) continue;
      if (!newState.any((n) => n.id == post.id)) {
        newState.add(post);
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
    await _box.delete('news');
  }
}

final newsProvider = StateNotifierProvider<NewsNotifier, List<NewsPost>>((ref) {
  final notifier = NewsNotifier();

  // 1. Listen for incoming news from mesh
  ref.listen(incomingNewsProvider, (previous, next) {
    if (next.hasValue) {
      notifier.syncFromPeer(next.value!);
    }
  });

  // 2. Listen for STATE changes (new local news) and PUSH immediately
  ref.listenSelf((previous, next) {
    final peers = ref.read(connectedPeersProvider).valueOrNull;
    if (peers != null && peers.isNotEmpty && next.isNotEmpty) {
      final manager = ref.read(wifiMeshManagerProvider);
      final ips = peers.map((p) => p.ipAddress).whereType<String>().toList();
      manager.syncNews(next, ips);
    }
  });

  // 3. Auto-sync news with mesh peers when new peers connect
  ref.listen(connectedPeersProvider, (previous, next) {
    if (next.hasValue && next.value!.isNotEmpty) {
      final manager = ref.read(wifiMeshManagerProvider);
      final news = notifier.state;
      if (news.isNotEmpty) {
        final ips = next.value!
            .map((p) => p.ipAddress)
            .whereType<String>()
            .toList();
        manager.syncNews(news, ips);
      }
    }
  });

  return notifier;
});
