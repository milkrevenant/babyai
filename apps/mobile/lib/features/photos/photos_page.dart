import "dart:convert";

import "package:flutter/material.dart";

import "../../core/config/app_env.dart";
import "../../core/i18n/app_i18n.dart";
import "../../core/network/babyai_api.dart";

enum _PhotoViewMode { tiles, albums }

enum _PhotoSortMode { album, date, views, likes }

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

  _PhotoViewMode _viewMode = _PhotoViewMode.tiles;
  _PhotoSortMode _sortMode = _PhotoSortMode.date;

  final List<_PhotoItem> _items = <_PhotoItem>[
    _PhotoItem(
      id: "p1",
      album: "일상",
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      views: 24,
      likes: 7,
      title: "오전 낮잠",
      color: const Color(0xFF7C7FB6),
    ),
    _PhotoItem(
      id: "p2",
      album: "일상",
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      views: 41,
      likes: 12,
      title: "분유 시간",
      color: const Color(0xFF5E6CA0),
    ),
    _PhotoItem(
      id: "p3",
      album: "외출",
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      views: 13,
      likes: 4,
      title: "공원 산책",
      color: const Color(0xFF7D6A9A),
    ),
    _PhotoItem(
      id: "p4",
      album: "가족",
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      views: 56,
      likes: 23,
      title: "주말 방문",
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
      case _PhotoSortMode.album:
        result.sort((a, b) {
          final int byAlbum = a.album.compareTo(b.album);
          if (byAlbum != 0) {
            return byAlbum;
          }
          return b.createdAt.compareTo(a.createdAt);
        });
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
      setState(
        () => _error = tr(
          context,
          ko: "오브젝트 키가 필요합니다.",
          en: "Object key is required.",
          es: "Se requiere object key.",
        ),
      );
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
      case _PhotoSortMode.album:
        return tr(context, ko: "앨범", en: "Album", es: "Album");
      case _PhotoSortMode.date:
        return tr(context, ko: "날짜", en: "Date", es: "Fecha");
      case _PhotoSortMode.views:
        return tr(context, ko: "조회수", en: "Views", es: "Vistas");
      case _PhotoSortMode.likes:
        return tr(context, ko: "좋아요", en: "Likes", es: "Me gusta");
    }
  }

  @override
  Widget build(BuildContext context) {
    const JsonEncoder encoder = JsonEncoder.withIndent("  ");
    final List<_PhotoItem> sorted = _sortedItems();
    final Map<String, List<_PhotoItem>> albumMap = <String, List<_PhotoItem>>{};
    for (final _PhotoItem item in sorted) {
      albumMap.putIfAbsent(item.album, () => <_PhotoItem>[]).add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _OvalIconChoice(
              selected: _viewMode == _PhotoViewMode.tiles,
              icon: Icons.grid_view_rounded,
              label: tr(context, ko: "타일", en: "Tiles", es: "Mosaico"),
              onTap: () => setState(() => _viewMode = _PhotoViewMode.tiles),
            ),
            _OvalIconChoice(
              selected: _viewMode == _PhotoViewMode.albums,
              icon: Icons.folder_copy_outlined,
              label: tr(context, ko: "앨범", en: "Albums", es: "Albumes"),
              onTap: () => setState(() => _viewMode = _PhotoViewMode.albums),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        if (_viewMode == _PhotoViewMode.tiles)
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
                      "조회 ${item.views}  좋아요 ${item.likes}",
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          )
        else
          Column(
            children: albumMap.entries
                .map((MapEntry<String, List<_PhotoItem>> entry) {
              final _PhotoItem head = entry.value.first;
              final int views = entry.value
                  .fold<int>(0, (int sum, _PhotoItem item) => sum + item.views);
              final int likes = entry.value
                  .fold<int>(0, (int sum, _PhotoItem item) => sum + item.likes);
              return Card(
                child: ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: head.color,
                        borderRadius: BorderRadius.circular(10)),
                    child:
                        const Icon(Icons.folder_outlined, color: Colors.white),
                  ),
                  title: Text(entry.key),
                  subtitle:
                      Text("${entry.value.length}장 | 조회 $views | 좋아요 $likes"),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: Text(tr(context,
              ko: "업로드 관리자", en: "Upload manager", es: "Gestor de carga")),
          subtitle: Text(
              "Album ID: ${AppEnv.albumId.isEmpty ? "(not set)" : AppEnv.albumId}"),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: <Widget>[
            FilledButton.icon(
              onPressed: _loading ? null : _createUploadUrl,
              icon: const Icon(Icons.link),
              label: Text(tr(context,
                  ko: "업로드 URL 생성", en: "Create upload URL", es: "Crear URL")),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _objectKeyController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: tr(context,
                    ko: "오브젝트 키", en: "Object key", es: "Object key"),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _downloadable,
              onChanged: _loading
                  ? null
                  : (bool value) => setState(() => _downloadable = value),
              title: Text(tr(context,
                  ko: "다운로드 허용", en: "Downloadable", es: "Descargable")),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _completeUpload,
              icon: const Icon(Icons.cloud_done_outlined),
              label: Text(tr(context,
                  ko: "업로드 완료", en: "Complete upload", es: "Completar carga")),
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

class _OvalIconChoice extends StatelessWidget {
  const _OvalIconChoice({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? color.primaryContainer.withValues(alpha: 0.92)
          : color.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
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
    required this.album,
    required this.createdAt,
    required this.views,
    required this.likes,
    required this.title,
    required this.color,
  });

  final String id;
  final String album;
  final DateTime createdAt;
  final int views;
  final int likes;
  final String title;
  final Color color;
}
