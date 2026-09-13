import 'package:flutter/material.dart';

import '../../core/models/engine_models.dart';

extension EngineResultPresentation on EngineResult {
  bool get isSuccessful => status == EngineRunStatus.success;

  bool get isUnavailable => status == EngineRunStatus.unavailable;

  bool get isFailed => status == EngineRunStatus.failed;

  bool get canDisplayOutput => isSuccessful && outputPath.isNotEmpty;

  bool get canDisplayMask => isSuccessful && maskPath.isNotEmpty;

  String get statusLabel => switch (status) {
        EngineRunStatus.success => '성공',
        EngineRunStatus.unavailable => '사용 불가',
        EngineRunStatus.failed => '실패',
      };

  String get provenanceLabel {
    final parts = <String>[
      if (backendUsed.isNotEmpty) backendUsed,
      if (provider.isNotEmpty) provider,
      if (modelVersion.isNotEmpty) modelVersion,
    ];
    return parts.isEmpty ? '실행 환경 정보 없음' : parts.join(' · ');
  }

  String get sessionLabel {
    if (sessionReused) return '세션 재사용(warm)';
    if (phaseTimingsMs.containsKey('model_load_ms')) return '새 세션(cold)';
    return '상주 세션 비사용';
  }
}

Color engineStatusColor(BuildContext context, EngineRunStatus status) {
  final colors = Theme.of(context).colorScheme;
  return switch (status) {
    EngineRunStatus.success => Colors.green.shade700,
    EngineRunStatus.unavailable => colors.outline,
    EngineRunStatus.failed => colors.error,
  };
}

String formatMetric(double? value, String suffix, {int fractionDigits = 1}) {
  if (value == null || !value.isFinite) return '—';
  return '${value.toStringAsFixed(fractionDigits)}$suffix';
}

class EngineStatusBadge extends StatelessWidget {
  const EngineStatusBadge(
      {super.key, required this.result, this.compact = false});

  final EngineResult result;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = engineStatusColor(context, result.status);
    return Tooltip(
      message: result.error?.trim().isNotEmpty == true
          ? result.error!
          : result.provenanceLabel,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_statusIcon(result.status),
                size: compact ? 11 : 13, color: color),
            const SizedBox(width: 4),
            Text(
              result.statusLabel,
              style: TextStyle(
                color: color,
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(EngineRunStatus status) => switch (status) {
        EngineRunStatus.success => Icons.check_circle_outline,
        EngineRunStatus.unavailable => Icons.block_outlined,
        EngineRunStatus.failed => Icons.error_outline,
      };
}
