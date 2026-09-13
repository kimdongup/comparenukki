import 'dart:io';
import 'package:flutter/material.dart';

class SafeNukkiImage extends StatefulWidget {
  final String path;
  final BoxFit fit;
  final int? targetCacheWidth;
  final int? targetCacheHeight;
  final String? cacheKey;

  const SafeNukkiImage({
    super.key,
    required this.path,
    this.fit = BoxFit.contain,
    this.targetCacheWidth = 600,
    this.targetCacheHeight,
    this.cacheKey,
  });

  @override
  State<SafeNukkiImage> createState() => _SafeNukkiImageState();
}

class _SafeNukkiImageState extends State<SafeNukkiImage> {
  static final Map<String, String?> _lastCacheKeys = {};

  @override
  void initState() {
    super.initState();
    _evictStaleFileImage();
  }

  @override
  void didUpdateWidget(covariant SafeNukkiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _evictStaleFileImage();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path.isEmpty) {
      return const Center(child: Text('경로 없음'));
    }

    if (_isAssetPath(widget.path)) {
      return _loadAsAsset(widget.path);
    }

    return Image.file(
      File(widget.path),
      key: ValueKey('${widget.path}:${widget.cacheKey ?? ''}'),
      fit: widget.fit,
      cacheWidth: widget.targetCacheWidth,
      cacheHeight: widget.targetCacheHeight,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) =>
          _buildErrorPlaceholder(widget.path),
    );
  }

  Widget _loadAsAsset(String rawPath) {
    return Image.asset(
      rawPath,
      key: ValueKey('$rawPath:${widget.cacheKey ?? ''}'),
      fit: widget.fit,
      cacheWidth: widget.targetCacheWidth,
      cacheHeight: widget.targetCacheHeight,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) =>
          _buildErrorPlaceholder(rawPath),
    );
  }

  bool _isAssetPath(String path) => path.startsWith('assets/');

  void _evictStaleFileImage() {
    final path = widget.path;
    if (path.isEmpty || _isAssetPath(path)) return;

    final wasSeen = _lastCacheKeys.containsKey(path);
    final previousCacheKey = _lastCacheKeys[path];
    if (wasSeen && previousCacheKey != widget.cacheKey) {
      final fileImage = FileImage(File(path));
      final resized = ResizeImage.resizeIfNeeded(
        widget.targetCacheWidth,
        widget.targetCacheHeight,
        fileImage,
      );
      PaintingBinding.instance.imageCache
        ..evict(fileImage)
        ..evict(resized);
    }
    _lastCacheKeys[path] = widget.cacheKey;
    if (_lastCacheKeys.length > 256) {
      _lastCacheKeys.remove(_lastCacheKeys.keys.first);
    }
  }

  Widget _buildErrorPlaceholder(String path) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, size: 28, color: Colors.grey),
          const SizedBox(height: 4),
          Text(
            '이미지 로드 실패\n'
            '(${path.replaceAll('\\', '/').split('/').last})',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
