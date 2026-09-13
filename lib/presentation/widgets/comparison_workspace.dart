import 'package:flutter/material.dart';

import '../../core/models/engine_models.dart';
import 'background_switcher.dart';
import 'curtain_slider_viewer.dart';
import 'sync_grid_viewer.dart';

class ComparisonWorkspace extends StatelessWidget {
  const ComparisonWorkspace({
    super.key,
    required this.currentImage,
    required this.results,
    required this.viewMode,
    required this.bgTheme,
    required this.curtainRatio,
    required this.curtainEngineA,
    required this.curtainEngineB,
    required this.isRunning,
    required this.progress,
    required this.activeEngineId,
    required this.onViewModeChanged,
    required this.onBackgroundThemeChanged,
    required this.onCurtainRatioChanged,
    required this.onCurtainEnginesChanged,
  });

  final SampleImageInfo currentImage;
  final Map<String, EngineResult> results;
  final ComparisonViewMode viewMode;
  final BackgroundTheme bgTheme;
  final double curtainRatio;
  final String curtainEngineA;
  final String curtainEngineB;
  final bool isRunning;
  final double progress;
  final String? activeEngineId;
  final ValueChanged<ComparisonViewMode> onViewModeChanged;
  final ValueChanged<BackgroundTheme> onBackgroundThemeChanged;
  final ValueChanged<double> onCurtainRatioChanged;
  final CurtainEnginesChanged onCurtainEnginesChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 8),
            child: Row(
              children: [
                Icon(Icons.compare_outlined, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Compare',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    currentImage.title,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                  ),
                ),
                if (results.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${results.length}개 결과',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              border: Border.symmetric(
                horizontal: BorderSide(color: colors.outlineVariant),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final modeSelector = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<ComparisonViewMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ComparisonViewMode.grid,
                        icon: Icon(Icons.grid_view, size: 14),
                        label: Text(
                          '동기화 그리드',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                      ButtonSegment(
                        value: ComparisonViewMode.curtainSlider,
                        icon: Icon(Icons.compare, size: 14),
                        label: Text(
                          '2단 슬라이더',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                      ButtonSegment(
                        value: ComparisonViewMode.maskOnly,
                        icon: Icon(Icons.visibility_outlined, size: 14),
                        label: Text(
                          '알파 마스크',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                    selected: {viewMode},
                    onSelectionChanged: (selection) =>
                        onViewModeChanged(selection.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                );
                final Widget backgroundSelector =
                    viewMode == ComparisonViewMode.maskOnly
                        ? const _MaskBackgroundNotice()
                        : BackgroundToolbarToggle(
                            currentTheme: bgTheme,
                            compact: constraints.maxWidth < 840,
                            onThemeChanged: onBackgroundThemeChanged,
                          );

                if (constraints.maxWidth < 760) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      modeSelector,
                      const SizedBox(height: 6),
                      backgroundSelector,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: modeSelector),
                    const SizedBox(width: 8),
                    backgroundSelector,
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildMainView()),
                if (isRunning)
                  Positioned(
                    top: 10,
                    right: 12,
                    child: IgnorePointer(
                      child: _BackgroundStatusPill(
                        progress: progress,
                        engineName: _activeEngineName,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? get _activeEngineName {
    final engineId = activeEngineId;
    if (engineId == null) return null;
    return results[engineId]?.name ?? engineId;
  }

  Widget _buildMainView() {
    switch (viewMode) {
      case ComparisonViewMode.grid:
      case ComparisonViewMode.maskOnly:
        return SyncGridViewer(
          currentImage: currentImage,
          results: results,
          bgTheme: bgTheme,
          showMaskOnly: viewMode == ComparisonViewMode.maskOnly,
          activeEngineId: activeEngineId,
        );
      case ComparisonViewMode.curtainSlider:
        return CurtainSliderViewer(
          currentImage: currentImage,
          results: results,
          bgTheme: bgTheme,
          initialSplitRatio: curtainRatio,
          engineA: curtainEngineA,
          engineB: curtainEngineB,
          onRatioChanged: onCurtainRatioChanged,
          onEnginesChanged: onCurtainEnginesChanged,
        );
    }
  }
}

class _MaskBackgroundNotice extends StatelessWidget {
  const _MaskBackgroundNotice();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '알파 마스크는 명암을 정확히 보기 위해 검정 배경으로 표시됩니다.',
      child: Chip(
        avatar: const Icon(Icons.contrast, size: 15),
        label: const Text(
          '마스크 배경 고정',
          style: TextStyle(fontSize: 10),
        ),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

class _BackgroundStatusPill extends StatelessWidget {
  const _BackgroundStatusPill({required this.progress, this.engineName});

  final double progress;
  final String? engineName;

  @override
  Widget build(BuildContext context) {
    final normalized = progress.clamp(0.0, 1.0);
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              engineName == null ? '백그라운드 측정 중' : '$engineName 측정 중',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '${(normalized * 100).round()}%',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
