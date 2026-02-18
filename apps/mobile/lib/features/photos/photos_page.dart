import "dart:async";
import "dart:io";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:image_picker/image_picker.dart";
import "package:share_plus/share_plus.dart";

import "../../core/config/app_env.dart";
import "../../core/config/session_store.dart";
import "../../core/i18n/app_i18n.dart";
import "../../core/network/babyai_api.dart";

enum PhotosViewMode { tiles, albums }

enum _PhotoSortMode { album, date }

enum _PhotoGroupingUnit { day, month, year }

class PhotosPage extends StatefulWidget {
  const PhotosPage({
    super.key,
    required this.viewMode,
  });

  final PhotosViewMode viewMode;

  @override
  State<PhotosPage> createState() => PhotosPageState();
}

class PhotosPageState extends State<PhotosPage> {
  final ImagePicker _picker = ImagePicker();

  bool _loading = false;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _error;
  String? _highlightPhotoId;

  _PhotoSortMode _sortMode = _PhotoSortMode.date;
  int _tileColumns = 3;
  int _scaleStartColumns = 3;
  List<_PhotoItem> _items = const <_PhotoItem>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPhotos());
  }

  Future<void> pickAndUploadFromGallery() async {
    if (_uploading) {
      return;
    }
    final XFile? selected = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 2560,
    );
    if (!mounted || selected == null) {
      return;
    }

    Timer? progressTimer;
    setState(() {
      _uploading = true;
      _uploadProgress = 0.07;
      _error = null;
    });
    progressTimer =
        Timer.periodic(const Duration(milliseconds: 120), (Timer timer) {
      if (!mounted || _uploadProgress >= 0.86) {
        return;
      }
      setState(() => _uploadProgress += 0.08);
    });

    try {
      final Map<String, dynamic> uploaded =
          await BabyAIApi.instance.uploadPhotoFromDevice(
        filePath: selected.path,
        downloadable: false,
      );
      progressTimer.cancel();
      if (mounted) {
        setState(() => _uploadProgress = 1);
      }
      await AppSessionStore.persistRuntimeState();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      await _loadPhotos(showLoader: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _uploading = false;
        _uploadProgress = 0;
        _highlightPhotoId = (uploaded["photo_id"] ?? "").toString();
      });
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(() => _highlightPhotoId = null);
        }
      });
    } catch (error) {
      progressTimer.cancel();
      if (!mounted) {
        return;
      }
      setState(() {
        _uploading = false;
        _uploadProgress = 0;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadPhotos({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final Map<String, dynamic> result =
          await BabyAIApi.instance.recentPhotos();
      final Object? rawList = result["photos"];
      final List<_PhotoItem> parsed = <_PhotoItem>[];
      if (rawList is List<dynamic>) {
        for (final dynamic row in rawList) {
          if (row is! Map<dynamic, dynamic>) {
            continue;
          }
          final String id = (row["photo_id"] ?? "").toString().trim();
          if (id.isEmpty) {
            continue;
          }
          final String createdRaw = (row["created_at"] ?? "").toString().trim();
          final DateTime createdAt =
              DateTime.tryParse(createdRaw)?.toLocal() ?? DateTime.now();
          final String albumId = (row["album_id"] ?? "").toString().trim();
          final String albumTitle =
              (row["album_title"] ?? "").toString().trim().isEmpty
                  ? ""
                  : (row["album_title"] ?? "").toString().trim();
          final String previewUrl = _resolvePhotoURL(
            (row["preview_url"] ?? row["original_url"] ?? "").toString(),
          );
          final String originalUrl = _resolvePhotoURL(
            (row["original_url"] ?? row["preview_url"] ?? "").toString(),
          );
          if (previewUrl.isEmpty && originalUrl.isEmpty) {
            continue;
          }
          parsed.add(
            _PhotoItem(
              id: id,
              albumId: albumId,
              album: albumTitle,
              createdAt: createdAt,
              previewUrl: previewUrl.isEmpty ? originalUrl : previewUrl,
              originalUrl: originalUrl.isEmpty ? previewUrl : originalUrl,
              downloadable: (row["downloadable"] ?? false) == true,
            ),
          );
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _items = parsed);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted && showLoader) {
        setState(() => _loading = false);
      }
    }
  }

  String _resolvePhotoURL(String raw) {
    final String url = raw.trim();
    if (url.isEmpty) {
      return "";
    }
    if (url.startsWith("http://") || url.startsWith("https://")) {
      return url;
    }
    final String base = AppEnv.apiBaseUrl.endsWith("/")
        ? AppEnv.apiBaseUrl.substring(0, AppEnv.apiBaseUrl.length - 1)
        : AppEnv.apiBaseUrl;
    if (url.startsWith("/")) {
      return "$base$url";
    }
    return "$base/$url";
  }

  String _sortLabel(BuildContext context, _PhotoSortMode mode) {
    switch (mode) {
      case _PhotoSortMode.album:
        return tr(context, ko: "앨범순", en: "Album", es: "Album");
      case _PhotoSortMode.date:
        return tr(context, ko: "최신순", en: "Date", es: "Fecha");
    }
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
    }
    return result;
  }

  String _relativeTime(BuildContext context, DateTime dateTime) {
    final Duration diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) {
      return tr(context, ko: "방금 전", en: "just now", es: "ahora");
    }
    if (diff.inHours < 1) {
      return tr(
        context,
        ko: "${diff.inMinutes}분 전",
        en: "${diff.inMinutes}m ago",
        es: "hace ${diff.inMinutes}m",
      );
    }
    if (diff.inDays < 1) {
      return tr(
        context,
        ko: "${diff.inHours}시간 전",
        en: "${diff.inHours}h ago",
        es: "hace ${diff.inHours}h",
      );
    }
    return tr(
      context,
      ko: "${diff.inDays}일 전",
      en: "${diff.inDays}d ago",
      es: "hace ${diff.inDays}d",
    );
  }

  String _albumLabel(BuildContext context, String albumTitle) {
    if (albumTitle.trim().isEmpty) {
      return tr(context, ko: "기본 앨범", en: "Default album", es: "Album base");
    }
    return albumTitle;
  }

  _PhotoGroupingUnit _groupingUnitForColumns() {
    if (_tileColumns <= 3) {
      return _PhotoGroupingUnit.day;
    }
    if (_tileColumns <= 5) {
      return _PhotoGroupingUnit.month;
    }
    return _PhotoGroupingUnit.year;
  }

  String _groupKey(DateTime date, _PhotoGroupingUnit unit) {
    switch (unit) {
      case _PhotoGroupingUnit.day:
        return "${date.year.toString().padLeft(4, "0")}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")}";
      case _PhotoGroupingUnit.month:
        return "${date.year.toString().padLeft(4, "0")}-${date.month.toString().padLeft(2, "0")}";
      case _PhotoGroupingUnit.year:
        return date.year.toString().padLeft(4, "0");
    }
  }

  String _groupLabel(
      BuildContext context, String key, _PhotoGroupingUnit unit) {
    switch (unit) {
      case _PhotoGroupingUnit.day:
        return key;
      case _PhotoGroupingUnit.month:
        return key;
      case _PhotoGroupingUnit.year:
        return "$key ${tr(context, ko: "년", en: "", es: "")}".trim();
    }
  }

  List<_PhotoGroup> _groupForTiles(
      BuildContext context, List<_PhotoItem> items) {
    final _PhotoGroupingUnit unit = _groupingUnitForColumns();
    final Map<String, List<_PhotoItem>> map = <String, List<_PhotoItem>>{};
    final List<String> order = <String>[];

    for (final _PhotoItem item in items) {
      final String key = _groupKey(item.createdAt, unit);
      if (!map.containsKey(key)) {
        map[key] = <_PhotoItem>[];
        order.add(key);
      }
      map[key]!.add(item);
    }

    return order
        .map(
          (String key) => _PhotoGroup(
            label: _groupLabel(context, key, unit),
            items: map[key]!,
          ),
        )
        .toList();
  }

  void _onTilesScaleStart(ScaleStartDetails details) {
    _scaleStartColumns = _tileColumns;
  }

  void _onTilesScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      return;
    }
    final int nextColumns =
        (_scaleStartColumns / details.scale).round().clamp(2, 6);
    if (nextColumns != _tileColumns && mounted) {
      setState(() => _tileColumns = nextColumns);
    }
  }

  Future<void> _openPhotoViewer(
    List<_PhotoItem> ordered,
    int initialIndex,
  ) async {
    if (initialIndex < 0 || initialIndex >= ordered.length) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _PhotoViewerPage(
          items: ordered,
          initialIndex: initialIndex,
          defaultAlbumLabel:
              tr(context, ko: "기본 앨범", en: "Default album", es: "Album base"),
          albumLinkBuilder: (String albumId) {
            if (albumId.trim().isEmpty) {
              return "";
            }
            final String babyId = BabyAIApi.activeBabyId;
            return "babyai://album/$albumId${babyId.isEmpty ? "" : "?baby_id=$babyId"}";
          },
        ),
      ),
    );
  }

  Widget _buildPhotoTile(
    BuildContext context,
    _PhotoItem item,
    List<_PhotoItem> ordered,
    int index,
  ) {
    final bool highlighted = item.id == _highlightPhotoId;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: highlighted ? 0.92 : 1, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double scale, Widget? child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openPhotoViewer(ordered, index),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Hero(
                tag: "photo_${item.id}",
                child: Image.network(
                  item.previewUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Text(
                  _relativeTime(context, item.createdAt),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTilesView(BuildContext context, List<_PhotoItem> sorted) {
    if (sorted.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          tr(
            context,
            ko: "업로드된 사진이 아직 없습니다.",
            en: "No uploaded photos yet.",
            es: "Aun no hay fotos subidas.",
          ),
        ),
      );
    }

    final List<_PhotoGroup> groups = _groupForTiles(context, sorted);

    return GestureDetector(
      onScaleStart: _onTilesScaleStart,
      onScaleUpdate: _onTilesScaleUpdate,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.pinch_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                tr(
                  context,
                  ko: "핀치로 타일 크기 조절",
                  en: "Pinch to resize tiles",
                  es: "Pellizca para ajustar",
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                "$_tileColumns ${tr(context, ko: "열", en: "cols", es: "cols")}",
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...groups.map((group) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    group.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: group.items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _tileColumns,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (BuildContext context, int index) {
                      final _PhotoItem item = group.items[index];
                      final int globalIndex = sorted.indexWhere(
                        (_PhotoItem each) => each.id == item.id,
                      );
                      return _buildPhotoTile(
                          context, item, sorted, globalIndex);
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _openAlbumGrid(
    BuildContext context,
    String albumTitle,
    List<_PhotoItem> items,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _AlbumPhotosPage(
          albumTitle: albumTitle,
          items: items,
          defaultAlbumLabel:
              tr(context, ko: "기본 앨범", en: "Default album", es: "Album base"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_PhotoItem> sorted = _sortedItems();
    final Map<String, List<_PhotoItem>> albumMap = <String, List<_PhotoItem>>{};
    for (final _PhotoItem item in sorted) {
      albumMap.putIfAbsent(item.album, () => <_PhotoItem>[]).add(item);
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _PhotoSortMode.values
                .map(
                  (_PhotoSortMode mode) => ChoiceChip(
                    selected: _sortMode == mode,
                    label: Text(_sortLabel(context, mode)),
                    onSelected: (_) => setState(() => _sortMode = mode),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _uploading
                ? LinearProgressIndicator(
                    value: _uploadProgress <= 0 ? null : _uploadProgress,
                  )
                : const SizedBox.shrink(),
          ),
          if (_loading) ...<Widget>[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              ko: "오른쪽 아래 + 버튼으로 사진을 업로드하세요. 사진 탭에서 개별 보기와 공유를 지원합니다.",
              en: "Use the + button to upload. Tap a photo for full view and sharing.",
              es: "Usa + para subir. Toca una foto para ver y compartir.",
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (BabyAIApi.activeAlbumId.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              "${tr(context, ko: "앨범 ID", en: "Album ID", es: "ID de album")}: ${BabyAIApi.activeAlbumId}",
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (widget.viewMode == PhotosViewMode.tiles)
            _buildTilesView(context, sorted)
          else if (sorted.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                tr(
                  context,
                  ko: "업로드된 사진이 아직 없습니다.",
                  en: "No uploaded photos yet.",
                  es: "Aun no hay fotos subidas.",
                ),
              ),
            )
          else
            Column(
              children: albumMap.entries
                  .map((MapEntry<String, List<_PhotoItem>> entry) {
                final _PhotoItem first = entry.value.first;
                return Card(
                  child: ListTile(
                    onTap: () => _openAlbumGrid(
                      context,
                      _albumLabel(context, entry.key),
                      entry.value,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        first.previewUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 44,
                          height: 44,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
                    ),
                    title: Text(_albumLabel(context, entry.key)),
                    subtitle: Text(
                      "${entry.value.length} ${tr(context, ko: "장", en: "photos", es: "fotos")}",
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _AlbumPhotosPage extends StatelessWidget {
  const _AlbumPhotosPage({
    required this.albumTitle,
    required this.items,
    required this.defaultAlbumLabel,
  });

  final String albumTitle;
  final List<_PhotoItem> items;
  final String defaultAlbumLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(albumTitle)),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemBuilder: (BuildContext context, int index) {
          final _PhotoItem item = items[index];
          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => _PhotoViewerPage(
                      items: items,
                      initialIndex: index,
                      defaultAlbumLabel: defaultAlbumLabel,
                      albumLinkBuilder: (String albumId) {
                        if (albumId.trim().isEmpty) {
                          return "";
                        }
                        return "babyai://album/$albumId";
                      },
                    ),
                  ),
                );
              },
              child: Hero(
                tag: "photo_${item.id}",
                child: Image.network(
                  item.previewUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhotoViewerPage extends StatefulWidget {
  const _PhotoViewerPage({
    required this.items,
    required this.initialIndex,
    required this.defaultAlbumLabel,
    required this.albumLinkBuilder,
  });

  final List<_PhotoItem> items;
  final int initialIndex;
  final String defaultAlbumLabel;
  final String Function(String albumId) albumLinkBuilder;

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late final PageController _pageController;
  late int _index;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  _PhotoItem get _current => widget.items[_index];

  String _extensionFromUrl(String url) {
    final String path = Uri.tryParse(url)?.path ?? url;
    final int dot = path.lastIndexOf(".");
    if (dot < 0) {
      return ".jpg";
    }
    final String ext = path.substring(dot).toLowerCase();
    if (ext.length > 8) {
      return ".jpg";
    }
    return ext;
  }

  String _albumShareLink(_PhotoItem item) {
    final String deepLink = widget.albumLinkBuilder(item.albumId);
    if (deepLink.isNotEmpty) {
      return deepLink;
    }
    return "babyai://album";
  }

  String _photoLink(_PhotoItem item) {
    if (item.originalUrl.trim().isNotEmpty) {
      return item.originalUrl;
    }
    return item.previewUrl;
  }

  Future<void> _sharePhotoFile(_PhotoItem item) async {
    final String source = _photoLink(item);
    if (source.trim().isEmpty) {
      return;
    }

    setState(() => _sharing = true);
    try {
      final Response<List<int>> response = await Dio().get<List<int>>(
        source,
        options: Options(responseType: ResponseType.bytes),
      );
      final List<int> bytes = response.data ?? <int>[];
      if (bytes.isEmpty) {
        throw Exception("Image data is empty");
      }
      final String ext = _extensionFromUrl(source);
      final String path =
          "${Directory.systemTemp.path}/babyai_share_${item.id}$ext";
      final File file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        text: "BabyAI Photo",
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  Future<void> _shareText(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    await Share.share(text);
  }

  Future<void> _copyText(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            context,
            ko: "링크를 복사했습니다.",
            en: "Link copied.",
            es: "Enlace copiado.",
          ),
        ),
      ),
    );
  }

  Future<void> _openShareSheet() async {
    final _PhotoItem item = _current;
    final String photoLink = _photoLink(item);
    final String albumLink = _albumShareLink(item);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: Text(
                  tr(
                    context,
                    ko: "사진 공유",
                    en: "Share photo",
                    es: "Compartir foto",
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_sharePhotoFile(item));
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: Text(
                  tr(
                    context,
                    ko: "사진 링크 공유",
                    en: "Share photo link",
                    es: "Compartir enlace",
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_shareText(photoLink));
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(
                  tr(
                    context,
                    ko: "앨범 링크 공유",
                    en: "Share album link",
                    es: "Compartir album",
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_shareText(albumLink));
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: Text(
                  tr(
                    context,
                    ko: "사진 링크 복사",
                    en: "Copy photo link",
                    es: "Copiar enlace",
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_copyText(photoLink));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final _PhotoItem current = _current;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.76),
        foregroundColor: Colors.white,
        title: Text(
          "${_index + 1} / ${widget.items.length}",
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _sharing ? null : _openShareSheet,
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (int next) => setState(() => _index = next),
            itemBuilder: (BuildContext context, int index) {
              final _PhotoItem item = widget.items[index];
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4.5,
                child: Center(
                  child: Hero(
                    tag: "photo_${item.id}",
                    child: Image.network(
                      _photoLink(item),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 44,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.52),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      current.album.trim().isEmpty
                          ? widget.defaultAlbumLabel
                          : current.album,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      current.createdAt.toString(),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoItem {
  const _PhotoItem({
    required this.id,
    required this.albumId,
    required this.album,
    required this.createdAt,
    required this.previewUrl,
    required this.originalUrl,
    required this.downloadable,
  });

  final String id;
  final String albumId;
  final String album;
  final DateTime createdAt;
  final String previewUrl;
  final String originalUrl;
  final bool downloadable;
}

class _PhotoGroup {
  const _PhotoGroup({required this.label, required this.items});

  final String label;
  final List<_PhotoItem> items;
}
