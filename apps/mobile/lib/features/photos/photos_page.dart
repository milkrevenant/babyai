import "dart:convert";

import "package:flutter/material.dart";

import "../../core/network/babyai_api.dart";

enum _PhotoSortMode { date, views, likes }

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  final TextEditingController _objectKeyController = TextEditingController();

  bool _downloadable = false;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _uploadUrl;
  Map<String, dynamic>? _completed;

  _PhotoSortMode _sortMode = _PhotoSortMode.date;

  final List<_PhotoItem> _items = <_PhotoItem>[
    _PhotoItem(
      id: "p1",
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      views: 24,
      likes: 7,
      title: "Morning nap",
      color: const Color(0xFF7C7FB6),
    ),
    _PhotoItem(
      id: "p2",
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      views: 41,
      likes: 12,
      title: "Formula time",
      color: const Color(0xFF5E6CA0),
    ),
    _PhotoItem(
      id: "p3",
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      views: 13,
      likes: 4,
      title: "Park walk",
      color: const Color(0xFF7D6A9A),
    ),
    _PhotoItem(
      id: "p4",
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      views: 56,
      likes: 23,
      title: "Weekend visit",
      color: const Color(0xFF8A7C58),
    ),
  ];

  @override
  void dispose() {
    _objectKeyController.dispose();
    super.dispose();
  }

  List<_PhotoItem> _sortedItems() {
    final List<_PhotoItem> result = List<_PhotoItem>.from(_items);
    switch (_sortMode) {
      case _PhotoSortMode.date:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _PhotoSortMode.views:
        result.sort((a, b) => b.views.compareTo(a.views));
      case _PhotoSortMode.likes:
        result.sort((a, b) => b.likes.compareTo(a.likes));
    }
    return result;
  }

  Future<void> _createUploadUrl() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> result =
          await BabyAIApi.instance.createUploadUrl();
      final String? objectKey = result["object_key"] as String?;
      if (objectKey != null && objectKey.isNotEmpty) {
        _objectKeyController.text = objectKey;
      }
      setState(() => _uploadUrl = result);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _completeUpload() async {
    final String objectKey = _objectKeyController.text.trim();
    if (objectKey.isEmpty) {
      setState(() => _error = "Object key is required.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result =
          await BabyAIApi.instance.completeUpload(
        objectKey: objectKey,
        downloadable: _downloadable,
      );
      setState(() => _completed = result);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _sortLabel(_PhotoSortMode mode) {
    switch (mode) {
      case _PhotoSortMode.date:
        return "Date";
      case _PhotoSortMode.views:
        return "Views";
      case _PhotoSortMode.likes:
        return "Likes";
    }
  }

  @override
  Widget build(BuildContext context) {
    const JsonEncoder encoder = JsonEncoder.withIndent("  ");
    final List<_PhotoItem> sorted = _sortedItems();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _PhotoSortMode.values
              .map(
                (_PhotoSortMode mode) => ChoiceChip(
                  selected: _sortMode == mode,
                  label: Text(_sortLabel(mode)),
                  onSelected: (_) => setState(() => _sortMode = mode),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sorted.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.8,
          ),
          itemBuilder: (BuildContext context, int index) {
            final _PhotoItem item = sorted[index];
            return Container(
              decoration: BoxDecoration(
                color: item.color,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 28,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "Views ${item.views}  Likes ${item.likes}",
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text("Upload manager"),
          subtitle: const Text("Upload and complete media file requests"),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: <Widget>[
            FilledButton.icon(
              onPressed: _loading ? null : _createUploadUrl,
              icon: const Icon(Icons.link),
              label: const Text("Create upload URL"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _objectKeyController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Object key",
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _downloadable,
              onChanged: _loading
                  ? null
                  : (bool value) => setState(() => _downloadable = value),
              title: const Text("Downloadable"),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _completeUpload,
              icon: const Icon(Icons.cloud_done_outlined),
              label: const Text("Complete upload"),
            ),
            if (_loading) ...<Widget>[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600)),
            ],
            if (_uploadUrl != null) ...<Widget>[
              const SizedBox(height: 10),
              _JsonPanel(
                  title: "Upload URL response",
                  data: _uploadUrl!,
                  encoder: encoder),
            ],
            if (_completed != null) ...<Widget>[
              const SizedBox(height: 10),
              _JsonPanel(
                  title: "Complete response",
                  data: _completed!,
                  encoder: encoder),
            ],
          ],
        ),
      ],
    );
  }
}

class _JsonPanel extends StatelessWidget {
  const _JsonPanel({
    required this.title,
    required this.data,
    required this.encoder,
  });

  final String title;
  final Map<String, dynamic> data;
  final JsonEncoder encoder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(encoder.convert(data)),
        ),
      ],
    );
  }
}

class _PhotoItem {
  const _PhotoItem({
    required this.id,
    required this.createdAt,
    required this.views,
    required this.likes,
    required this.title,
    required this.color,
  });

  final String id;
  final DateTime createdAt;
  final int views;
  final int likes;
  final String title;
  final Color color;
}
