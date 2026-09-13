import 'package:flutter/material.dart';

import '../../core/models/engine_models.dart';
import 'background_switcher.dart';
import 'code_snippet_dialog.dart';
import 'engine_result_presentation.dart';
import 'safe_nukki_image.dart';

class SyncGridViewer extends StatelessWidget {
  const SyncGridViewer({
    super.key,
    required this.currentImage,
    required this.results,
    required this.bgTheme,
    this.showMaskOnly = false,
    this.activeEngineId,
  });

  final SampleImageInfo currentImage;
  final Map<String, EngineResult> results;
  final BackgroundTheme bgTheme;
  final bool showMaskOnly;
  final String? activeEngineId;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return _EmptyComparison(currentImage: currentImage);
    }

    final engineList = results.values.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = constraints.maxWidth < 520 ? 520.0 : 310.0;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth < 520 ? 1.05 : 0.82,
          ),
          itemCount: engineList.length,
          itemBuilder: (context, index) {
            final engine = engineList[index];
            return _EngineResultCard(
              key: ValueKey(engine.engineId),
              engine: engine,
              bgTheme: bgTheme,
              showMaskOnly: showMaskOnly,
              isActive: activeEngineId == engine.engineId,
            );
          },
        );
      },
    );
  }
}

class _EmptyComparison extends StatelessWidget {
  const _EmptyComparison({required this.currentImage});

  final SampleImageInfo currentImage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 360;
        final previewHeight = (constraints.maxHeight * 0.42)
            .clamp(compactHeight ? 64.0 : 96.0, 180.0);
        final previewWidth = (previewHeight * 4 / 3).clamp(96.0, 240.0);
        return SingleChildScrollView(
          padding: EdgeInsets.all(compactHeight ? 12 : 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - (compactHeight ? 24 : 56))
                  .clamp(0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: previewHeight,
                      width: previewWidth,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SafeNukkiImage(
                        path: currentImage.assetPath,
                        fit: BoxFit.cover,
                        targetCacheWidth: 480,
                        targetCacheHeight: 360,
                      ),
                    ),
                    SizedBox(height: compactHeight ? 10 : 20),
                    Text(
                      '비교할 결과가 아직 없습니다',
                      style: TextStyle(
                        fontSize: compactHeight ? 14 : 17,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '사진을 선택한 뒤 ‘벤치마크 실행’을 누르세요.\n'
                      '선택만으로는 연산이 시작되지 않습니다.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.35,
                        fontSize: compactHeight ? 11 : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EngineResultCard extends StatelessWidget {
  const _EngineResultCard({
    super.key,
    required this.engine,
    required this.bgTheme,
    required this.showMaskOnly,
    required this.isActive,
  });

  final EngineResult engine;
  final BackgroundTheme bgTheme;
  final bool showMaskOnly;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDisplay =
        showMaskOnly ? engine.canDisplayMask : engine.canDisplayOutput;
    final imagePath = showMaskOnly ? engine.maskPath : engine.outputPath;

    return Card(
      elevation: isActive ? 5 : 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive
              ? theme.colorScheme.primary
              : engine.isFailed
                  ? theme.colorScheme.error.withValues(alpha: 0.45)
                  : theme.colorScheme.outlineVariant,
          width: isActive ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.55),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        engine.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: EngineStatusBadge(
                              result: engine,
                              compact: true,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              engine.provider.isEmpty
                                  ? engine.framework
                                  : engine.provider,
                              style: TextStyle(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.code, size: 18),
                  tooltip: '측정 경로 재현 코드 보기',
                  visualDensity: VisualDensity.compact,
                  onPressed: engine.codeSnippet.isEmpty
                      ? null
                      : () => CodeSnippetDialog.show(context, engine),
                ),
              ],
            ),
          ),
          if (isActive) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: BackgroundPatternWidget(
              theme: showMaskOnly ? BackgroundTheme.pureBlack : bgTheme,
              child: canDisplay
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: SafeNukkiImage(
                          path: imagePath,
                          cacheKey: engine.cacheKey,
                        ),
                      ),
                    )
                  : _ResultUnavailable(result: engine),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 5,
              children: [
                _MetricBadge(
                  icon: Icons.timer_outlined,
                  text: formatMetric(engine.latencyMs, ' ms'),
                  color: Colors.orange,
                ),
                _MetricBadge(
                  icon: Icons.memory,
                  text: formatMetric(engine.peakMemoryMb, ' MB'),
                  color: Colors.blue,
                ),
                _MetricBadge(
                  icon: Icons.monitor_heart_outlined,
                  text: formatMetric(engine.peakRssMb, ' MB RSS'),
                  color: Colors.teal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultUnavailable extends StatelessWidget {
  const _ResultUnavailable({required this.result});

  final EngineResult result;

  @override
  Widget build(BuildContext context) {
    final color = engineStatusColor(context, result.status);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 34, color: color),
            const SizedBox(height: 8),
            Text(
              result.statusLabel,
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
            if (result.error?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 5),
              Text(
                result.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color.shade700),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color.shade800,
          ),
        ),
      ],
    );
  }
}
