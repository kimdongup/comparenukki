import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/models/engine_models.dart';
import 'benchmark_action_button.dart';
import 'safe_nukki_image.dart';

class PhotoSourcePanel extends StatelessWidget {
  const PhotoSourcePanel({
    super.key,
    required this.currentImage,
    required this.samples,
    required this.isRunning,
    required this.progress,
    required this.benchmarkPhase,
    required this.activeEngineName,
    required this.workerSupported,
    required this.onSampleSelected,
    required this.onImageUploaded,
    required this.onRun,
    required this.onCancel,
  });

  final SampleImageInfo currentImage;
  final List<SampleImageInfo> samples;
  final bool isRunning;
  final double progress;
  final BenchmarkPhase benchmarkPhase;
  final String? activeEngineName;
  final bool workerSupported;
  final ValueChanged<SampleImageInfo> onSampleSelected;
  final ValueChanged<String> onImageUploaded;
  final VoidCallback onRun;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const _PanelHeading(
                  icon: Icons.add_photo_alternate_outlined,
                  title: '사진 추가',
                  subtitle: '비교할 원본을 선택하세요',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 1.65,
                          child: ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: SafeNukkiImage(
                              path: currentImage.assetPath,
                              fit: BoxFit.cover,
                              targetCacheWidth: 840,
                              targetCacheHeight: 510,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    currentImage.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 3, 12, 9),
                  child: Text(
                    currentImage.challengePoint,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.35,
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.upload_file_outlined, size: 17),
                    label: const Text('내 이미지 추가'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Text(
                    '샘플 이미지',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
                for (var index = 0; index < samples.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _SampleImageTile(
                      sample: samples[index],
                      isSelected: currentImage.id == samples[index].id,
                      onTap: () => onSampleSelected(samples[index]),
                    ),
                  ),
                  if (index != samples.length - 1) const SizedBox(height: 3),
                ],
                const SizedBox(height: 6),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: _BenchmarkStatusCard(
              isRunning: isRunning,
              progress: progress,
              phase: benchmarkPhase,
              activeEngineName: activeEngineName,
              workerSupported: workerSupported,
              onRun: onRun,
              onCancel: onCancel,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final selection = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = selection?.files.single.path;
    if (path != null && path.isNotEmpty) onImageUploaded(path);
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _SampleImageTile extends StatelessWidget {
  const _SampleImageTile({
    required this.sample,
    required this.isSelected,
    required this.onTap,
  });

  final SampleImageInfo sample;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? colors.primaryContainer.withValues(alpha: 0.7)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: SafeNukkiImage(
                    path: sample.assetPath,
                    fit: BoxFit.cover,
                    targetCacheWidth: 96,
                    targetCacheHeight: 96,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sample.title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? colors.primary : colors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sample.subtitle,
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, size: 17, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenchmarkStatusCard extends StatelessWidget {
  const _BenchmarkStatusCard({
    required this.isRunning,
    required this.progress,
    required this.phase,
    required this.activeEngineName,
    required this.workerSupported,
    required this.onRun,
    required this.onCancel,
  });

  final bool isRunning;
  final double progress;
  final BenchmarkPhase phase;
  final String? activeEngineName;
  final bool workerSupported;
  final VoidCallback onRun;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final normalizedProgress = progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isRunning ? Icons.sync : _phaseIcon(phase),
                size: 16,
                color: isRunning ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  workerSupported ? _phaseLabel(phase) : '데스크톱 실행 전용',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              if (isRunning)
                Text(
                  '${(normalizedProgress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
            ],
          ),
          if (isRunning) ...[
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: normalizedProgress > 0 ? normalizedProgress : null,
              minHeight: 5,
              borderRadius: BorderRadius.circular(99),
            ),
            if (activeEngineName != null) ...[
              const SizedBox(height: 5),
              Text(
                '$activeEngineName 실행 중',
                style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ] else ...[
            const SizedBox(height: 5),
            Text(
              workerSupported
                  ? '사진 선택 후 직접 실행해야 측정을 시작합니다.'
                  : '로컬 Python 워커는 macOS·Windows·Linux에서 실행됩니다.',
              style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 9),
          BenchmarkActionButton(
            isRunning: isRunning,
            workerSupported: workerSupported,
            onRun: onRun,
            onCancel: onCancel,
          ),
        ],
      ),
    );
  }

  String _phaseLabel(BenchmarkPhase phase) => switch (phase) {
        BenchmarkPhase.idle => '실행 대기',
        BenchmarkPhase.starting => '작업 준비 중',
        BenchmarkPhase.running => '백그라운드 측정 중',
        BenchmarkPhase.completed => '측정 완료',
        BenchmarkPhase.completedWithIssues => '일부 엔진 측정 완료',
        BenchmarkPhase.cancelled => '실행 취소됨',
        BenchmarkPhase.failed => '실행 실패',
      };

  IconData _phaseIcon(BenchmarkPhase phase) => switch (phase) {
        BenchmarkPhase.idle => Icons.pause_circle_outline,
        BenchmarkPhase.starting => Icons.hourglass_top,
        BenchmarkPhase.running => Icons.sync,
        BenchmarkPhase.completed => Icons.check_circle_outline,
        BenchmarkPhase.completedWithIssues => Icons.warning_amber_rounded,
        BenchmarkPhase.cancelled => Icons.cancel_outlined,
        BenchmarkPhase.failed => Icons.error_outline,
      };
}
