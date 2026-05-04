import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/news_post.dart';
import '../../providers/news_providers.dart';
import '../../providers/network_providers.dart';

class NewsFeedScreen extends ConsumerStatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  ConsumerState<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedScreen> {
  NewsCategory? _filterCategory;

  @override
  Widget build(BuildContext context) {
    final allNews = ref.watch(newsProvider);
    final news = _filterCategory == null
        ? allNews
        : allNews.where((n) => n.category == _filterCategory).toList();

    return Scaffold(
      body: Column(
        children: [
          // Category Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'ALL',
                    isSelected: _filterCategory == null,
                    color: Colors.blueAccent,
                    onTap: () => setState(() => _filterCategory = null),
                  ),
                  const SizedBox(width: 8),
                  ...NewsCategory.values.map((cat) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: cat.label,
                          isSelected: _filterCategory == cat,
                          color: Color(cat.colorValue),
                          onTap: () =>
                              setState(() => _filterCategory = cat),
                        ),
                      )),
                ],
              ),
            ),
          ),

          // News Feed
          Expanded(
            child: news.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.newspaper,
                            size: 64,
                            color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        const Text(
                          'NO LOCAL NEWS YET',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create a post or receive from mesh peers',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: news.length,
                    itemBuilder: (context, index) {
                      final post = news[index];
                      return _NewsCard(post: post);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreatePostModal(context, ref),
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.edit, color: Colors.white),
        label: const Text('POST',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  void _showCreatePostModal(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    NewsCategory selectedCategory = NewsCategory.general;

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
                          color: Colors.blueAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.newspaper,
                            color: Colors.blueAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text('NEW LOCAL POST',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Title (e.g. "Water available at...")',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Details...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  const Text('CATEGORY',
                      style: TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: NewsCategory.values.map((cat) {
                      final isSelected = selectedCategory == cat;
                      return ChoiceChip(
                        label: Text('${cat.emoji} ${cat.label}'),
                        selected: isSelected,
                        selectedColor: Color(cat.colorValue).withValues(alpha: 0.3),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Color(cat.colorValue)
                              : Colors.grey,
                          fontSize: 11,
                        ),
                        side: BorderSide(
                          color: isSelected
                              ? Color(cat.colorValue)
                              : Colors.grey.withValues(alpha: 0.3),
                        ),
                        onSelected: (_) =>
                            setModalState(() => selectedCategory = cat),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (titleController.text.isNotEmpty) {
                          ref.read(newsProvider.notifier).addPost(
                                titleController.text,
                                bodyController.text,
                                selectedCategory,
                              );
                          // Sync to peers immediately
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
                                .syncNews(ref.read(newsProvider), ips);
                          }
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text('BROADCAST TO MESH',
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
// NEWS CARD
// =============================================================================

class _NewsCard extends StatelessWidget {
  final NewsPost post;
  const _NewsCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final catColor = Color(post.category.colorValue);
    final remaining = post.timeRemaining;
    final ttlMinutes = remaining.inMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: catColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with category badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: catColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${post.category.emoji} ${post.category.label}',
                    style: TextStyle(
                      color: catColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(),
                if (post.hopCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.route,
                            size: 10, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${post.hopCount} hops',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  post.timeAgo,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (post.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    post.body,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // TTL Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 12,
                  color: ttlMinutes < 10
                      ? Colors.redAccent
                      : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  ttlMinutes > 0 ? '${ttlMinutes}m remaining' : 'Expiring...',
                  style: TextStyle(
                    color:
                        ttlMinutes < 10 ? Colors.redAccent : Colors.grey,
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Icon(Icons.wifi_tethering,
                    size: 12, color: Colors.blueAccent.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Text(
                  'MESH PROPAGATED',
                  style: TextStyle(
                    color: Colors.blueAccent.withValues(alpha: 0.5),
                    fontSize: 9,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FILTER CHIP
// =============================================================================

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.grey,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
