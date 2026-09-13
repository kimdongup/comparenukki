import 'package:flutter/material.dart';

import '../../core/models/engine_models.dart';
import 'background_switcher.dart';
import 'engine_result_presentation.dart';
import 'safe_nukki_image.dart';

typedef CurtainEnginesChanged = void Function(String engineA, String engineB);

class CurtainSliderViewer extends StatefulWidget {
  const CurtainSliderViewer({
    super.key,
    required this.currentImage,
    required this.results,
    required this.bgTheme,
    this.initialSplitRatio = 0.5,
    required this.engineA,
    required this.engineB,
    required this.onRatioChanged,
    required this.onEnginesChanged,
  });

  final SampleImageInfo currentImage;
  final Map<String, EngineResult> results;
  final BackgroundTheme bgTheme;
  final double initialSplitRatio;
  final String engineA;
  final String engineB;
  final ValueChanged<double> onRatioChanged;
  final CurtainEnginesChanged onEnginesChanged;

  @override
  State<CurtainSliderViewer> createState() => _CurtainSliderViewerState();
}

class _CurtainSliderViewerState extends State<CurtainSliderViewer> {
  late final ValueNotifier<double> _ratioNotifier;

  @override
  void initState() {
    super.initState();
    _ratioNotifier = ValueNotifier<double>(widget.initialSplitRatio);
  }

  @override
  void didUpdateWidget(covariant CurtainSliderViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSplitRatio != widget.initialSplitRatio &&
        _ratioNotifier.value != widget.initialSplitRatio) {
      _ratioNotifier.value = widget.initialSplitRatio;
    }
  }

  @override
  void dispose() {
    _ratioNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayableResults = widget.results.values
        .where((result) => result.canDisplayOutput)
        .toList();
    final options = <_EngineOption>[
      const _EngineOption(id: 'original', label: 'Original (원본 이미지)'),
      ...displayableResults.map(
        (result) => _EngineOption(
          id: result.engineId,
          label: result.name,
        ),
      ),
    ];
    final selectedA = widget.engineA.isEmpty ? 'original' : widget.engineA;
    final selectedB = widget.engineB.isEmpty ? 'original' : widget.engineB;
    for (final selected in {selectedA, selectedB}) {
      if (!options.any((option) => option.id == selected)) {
        final result = widget.results[selected];
        options.add(
          _EngineOption(
            id: selected,
            label: result == null
                ? '$selected (결과 없음)'
                : '${result.name} (${result.statusLabel})',
          ),
        );
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final left = _EngineSelector(
                sideLabel: '좌측',
                value: selectedA,
                options: options,
                color: Colors.blue,
                onChanged: (value) => widget.onEnginesChanged(value, selectedB),
              );
              final right = _EngineSelector(
                sideLabel: '우측',
                value: selectedB,
                options: options,
                color: Colors.purple,
                onChanged: (value) => widget.onEnginesChanged(selectedA, value),
              );
              if (constraints.maxWidth < 560) {
                if (MediaQuery.sizeOf(context).height < 500) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 560,
                      child: _horizontalSelectors(left, right),
                    ),
                  );
                }
                return Column(
                  children: [
                    left,
                    const SizedBox(height: 6),
                    right,
                  ],
                );
              }
              return _horizontalSelectors(left, right);
            },
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final targetCacheWidth = (constraints.maxWidth *
                        MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(600, 4096)
                    .toInt();
                // These layers are constructed once for this widget build and reused
                // by ValueListenableBuilder while only the clip and handle move.
                final leftLayer = RepaintBoundary(
                  child: BackgroundPatternWidget(
                    theme: widget.bgTheme,
                    child: Center(
                      child: _buildImageWidget(selectedA, targetCacheWidth),
                    ),
                  ),
                );
                final rightLayer = RepaintBoundary(
                  child: BackgroundPatternWidget(
                    theme: widget.bgTheme,
                    child: Center(
                      child: _buildImageWidget(selectedB, targetCacheWidth),
                    ),
                  ),
                );

                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) {
                      _ratioNotifier.value =
                          (details.localPosition.dx / constraints.maxWidth)
                              .clamp(0.02, 0.98);
                    },
                    onHorizontalDragEnd: (_) =>
                        widget.onRatioChanged(_ratioNotifier.value),
                    child: ValueListenableBuilder<double>(
                      valueListenable: _ratioNotifier,
                      builder: (context, ratio, _) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            rightLayer,
                            ClipRect(
                              clipBehavior: Clip.hardEdge,
                              clipper: CurtainClipper(ratio: ratio),
                              child: leftLayer,
                            ),
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: constraints.maxWidth * ratio - 1.5,
                              child: IgnorePointer(
                                child: _CurtainHandle(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              left: 12,
                              child: _SideBadge(
                                label: _labelFor(selectedA),
                                color: Colors.blue,
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: _SideBadge(
                                label: _labelFor(selectedB),
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _horizontalSelectors(Widget left, Widget right) => Row(
        children: [
          Expanded(child: left),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'VS',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: right),
        ],
      );

  String _labelFor(String engineId) {
    if (engineId == 'original') return 'Original';
    return widget.results[engineId]?.name ?? engineId;
  }

  Widget _buildImageWidget(String engineId, int targetCacheWidth) {
    if (engineId == 'original') {
      return SafeNukkiImage(
        path: widget.currentImage.assetPath,
        targetCacheWidth: targetCacheWidth,
      );
    }

    final result = widget.results[engineId];
    if (result == null || !result.canDisplayOutput) {
      return const _NoCurtainResult();
    }
    return SafeNukkiImage(
      path: result.outputPath,
      cacheKey: result.cacheKey,
      targetCacheWidth: targetCacheWidth,
    );
  }
}

class _EngineOption {
  const _EngineOption({required this.id, required this.label});

  final String id;
  final String label;
}

class _EngineSelector extends StatelessWidget {
  const _EngineSelector({
    required this.sideLabel,
    required this.value,
    required this.options,
    required this.color,
    required this.onChanged,
  });

  final String sideLabel;
  final String value;
  final List<_EngineOption> options;
  final MaterialColor color;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option.id,
                  child: Text(
                    '$sideLabel: ${option.label}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _CurtainHandle extends StatelessWidget {
  const _CurtainHandle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      color: Colors.white,
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(Icons.compare_arrows, size: 20, color: color),
        ),
      ),
    );
  }
}

class _SideBadge extends StatelessWidget {
  const _SideBadge({required this.label, required this.color});

  final String label;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _NoCurtainResult extends StatelessWidget {
  const _NoCurtainResult();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 5),
              const Text('표시할 결과 없음'),
            ],
          ),
        ),
      ),
    );
  }
}

class CurtainClipper extends CustomClipper<Rect> {
  CurtainClipper({required this.ratio});

  final double ratio;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * ratio, size.height);

  @override
  bool shouldReclip(covariant CurtainClipper oldClipper) =>
      oldClipper.ratio != ratio;
}
