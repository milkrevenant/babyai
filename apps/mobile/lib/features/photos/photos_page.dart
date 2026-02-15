import "dart:convert";

import "package:flutter/material.dart";

import "../../core/config/app_env.dart";
import "../../core/network/babylog_api.dart";

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

  @override
  void dispose() {
    _objectKeyController.dispose();
    super.dispose();
  }

  Future<void> _createUploadUrl() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> result = await BabyLogApi.instance.createUploadUrl();
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
      final Map<String, dynamic> result = await BabyLogApi.instance.completeUpload(
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

  @override
  Widget build(BuildContext context) {
    const JsonEncoder encoder = JsonEncoder.withIndent("  ");

    return Scaffold(
      appBar: AppBar(title: const Text("Photo Share")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text("Album ID: ${AppEnv.albumId.isEmpty ? "(not set)" : AppEnv.albumId}"),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _createUploadUrl,
            icon: const Icon(Icons.link),
            label: const Text("Create Upload URL"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _objectKeyController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Object key",
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _downloadable,
            onChanged: _loading ? null : (bool value) => setState(() => _downloadable = value),
            title: const Text("Downloadable"),
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _completeUpload,
            icon: const Icon(Icons.cloud_done_outlined),
            label: const Text("Complete Upload"),
          ),
          if (_loading) ...<Widget>[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_uploadUrl != null) ...<Widget>[
            const SizedBox(height: 16),
            const Text(
              "Upload URL Response",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(encoder.convert(_uploadUrl)),
            ),
          ],
          if (_completed != null) ...<Widget>[
            const SizedBox(height: 16),
            const Text(
              "Complete Response",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(encoder.convert(_completed)),
            ),
          ],
        ],
      ),
    );
  }
}
