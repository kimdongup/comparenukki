import 'package:flutter/material.dart';

import '../../core/models/engine_models.dart';
import 'code_snippet_dialog.dart';
import 'engine_result_presentation.dart';

class MetricsTableView extends StatelessWidget {
  const MetricsTableView({
    super.key,
    required this.results,
    this.compact = false,
    this.padding = const EdgeInsets.all(20),
  });

  final Map<String, EngineResult> results;
  final bool compact;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const _EmptyMetrics();
    }

    final allResults = results.values.toList()..sort(_compareResults);
    final rankable = allResults.where((result) => result.isRankable).toList();
    final rankingGroups = <({String label, List<EngineResult> results})>[
      if (rankable.any((result) => !result.sessionReused))
        (
          label: 'cold/비상주',
          results: rankable.where((result) => !result.sessionReused).toList(),
        ),
      if (rankable.any((result) => result.sessionReused))
        (
          label: 'warm',
          results: rankable.where((result) => result.sessionReused).toList(),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumns = !compact && constraints.maxWidth >= 760;
        final charts = <Widget>[
          for (final group in rankingGroups) ...[
            _MetricRankingCard(
              title: '처리 시간 · ${group.label}',
              subtitle: '낮을수록 빠름',
              icon: Icons.timer_outlined,
              color: Colors.orange,
              results: group.results,
              valueOf: (result) => result.latencyMs,
              valueLabel: (value) => formatMetric(value, ' ms'),
            ),
            _MetricRankingCard(
              title: '추가 피크 메모리 · ${group.label}',
              subtitle: '실행 기준 RSS 증가량',
              icon: Icons.memory_outlined,
              color: Colors.blue,
              results: group.results,
              valueOf: (result) => result.peakMemoryMb,
              valueLabel: (value) => formatMetric(value, ' MB'),
            ),
          ],
        ];

        return Scrollbar(
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '지표 비교',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  '성공했고 백엔드가 순위를 허용한 결과만 후보가 됩니다. '
                  '각 지표는 유효한 값만 사용하고 cold/비상주와 warm을 분리합니다.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ResultSummary(results: allResults),
                const SizedBox(height: 16),
                if (useColumns) ...[
                  for (var index = 0; index < charts.length; index += 2) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: charts[index]),
                        if (index + 1 < charts.length) ...[
                          const SizedBox(width: 12),
                          Expanded(child: charts[index + 1]),
                        ],
                      ],
                    ),
                    if (index + 2 < charts.length) const SizedBox(height: 10),
                  ],
                ] else
                  ...charts.expand(
                    (chart) => [chart, const SizedBox(height: 10)],
                  ),
                const SizedBox(height: 12),
                Text(
                  '전체 실행 결과',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                for (final result in allResults) ...[
                  _EngineMetricDetails(result: result),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static int _compareResults(EngineResult a, EngineResult b) {
    if (a.isRankable != b.isRankable) return a.isRankable ? -1 : 1;
    final aLatency = a.latencyMs?.isFinite == true ? a.latencyMs : null;
    final bLatency = b.latencyMs?.isFinite == true ? b.latencyMs : null;
    if (aLatency != null && bLatency != null) {
      final comparison = aLatency.compareTo(bLatency);
      if (comparison != 0) return comparison;
    } else if (aLatency != null) {
      return -1;
    } else if (bLatency != null) {
      return 1;
    }
    return a.name.compareTo(b.name);
  }
}

class _EmptyMetrics extends StatelessWidget {
  const _EmptyMetrics();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '지표 비교',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.query_stats, size: 42, color: colors.outline),
                  const SizedBox(height: 12),
                  const Text(
                    '비교할 지표가 없습니다',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '벤치마크를 실행하면 모든 엔진 결과가\n'
                    '상태와 함께 표시됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.results});

  final List<EngineResult> results;

  @override
  Widget build(BuildContext context) {
    int count(EngineRunStatus status) =>
        results.where((result) => result.status == status).length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _SummaryChip(
          label: '순위 허용',
          count: results.where((result) => result.isRankable).length,
          color: Colors.green,
        ),
        _SummaryChip(
          label: '순위 제외',
          count: results
              .where(
                (result) =>
                    result.status == EngineRunStatus.success &&
                    !result.isRankable,
              )
              .length,
          color: Colors.orange,
        ),
        _SummaryChip(
          label: '사용 불가',
          count: count(EngineRunStatus.unavailable),
          color: Colors.grey,
        ),
        _SummaryChip(
          label: '실패',
          count: count(EngineRunStatus.failed),
          color: Colors.red,
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color.shade700,
        ),
      ),
    );
  }
}

typedef _MetricSelector = double? Function(EngineResult result);
typedef _MetricLabel = String Function(double? value);

class _MetricRankingCard extends StatelessWidget {
  const _MetricRankingCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.results,
    required this.valueOf,
    required this.valueLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final MaterialColor color;
  final List<EngineResult> results;
  final _MetricSelector valueOf;
  final _MetricLabel valueLabel;

  @override
  Widget build(BuildContext context) {
    final ranked = results
        .where((result) => valueOf(result)?.isFinite == true)
        .toList()
      ..sort((a, b) => valueOf(a)!.compareTo(valueOf(b)!));
    final maxValue = ranked.isEmpty
        ? 0.0
        : ranked
            .map((result) => valueOf(result)!)
            .reduce((a, b) => a > b ? a : b);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: color.shade700),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (ranked.isEmpty)
              Text(
                '유효한 성공 측정값 없음',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (var index = 0; index < ranked.length; index++) ...[
                _RankingBar(
                  rank: index + 1,
                  result: ranked[index],
                  value: valueOf(ranked[index])!,
                  label: valueLabel(valueOf(ranked[index])),
                  maxValue: maxValue,
                  color: color,
                ),
                if (index != ranked.length - 1) const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _RankingBar extends StatelessWidget {
  const _RankingBar({
    required this.rank,
    required this.result,
    required this.value,
    required this.label,
    required this.maxValue,
    required this.color,
  });

  final int rank;
  final EngineResult result;
  final double value;
  final String label;
  final double maxValue;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.04, 1.0);
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: color.shade800,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: Text(
                result.name,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: ratio,
            color: color.shade600,
            backgroundColor: color.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }
}

class _EngineMetricDetails extends StatelessWidget {
  const _EngineMetricDetails({required this.result});

  final EngineResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.name,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              EngineStatusBadge(result: result, compact: true),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _DetailMetric(
                label: '시간',
                value: formatMetric(result.latencyMs, ' ms'),
              ),
              _DetailMetric(
                label: '추가 메모리',
                value: formatMetric(result.peakMemoryMb, ' MB'),
              ),
              _DetailMetric(
                label: '피크 RSS',
                value: formatMetric(result.peakRssMb, ' MB'),
              ),
              _DetailMetric(
                label: '기준 RSS',
                value: formatMetric(result.baselineRssMb, ' MB'),
              ),
              _DetailMetric(
                label: '마스크 compactness(진단)',
                value: result.maskCompactness == null
                    ? '—'
                    : result.maskCompactness!.toStringAsFixed(3),
              ),
              _DetailMetric(
                label: '해상도',
                value: result.resolution.isEmpty ? '—' : result.resolution,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '${result.provenanceLabel} · ${result.sessionLabel}',
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
          if (result.phaseTimingsMs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              result.phaseTimingsMs.entries
                  .map((entry) =>
                      '${entry.key} ${entry.value.toStringAsFixed(1)}ms')
                  .join(' · '),
              style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
            ),
          ],
          if (result.inputSha256.isNotEmpty) ...[
            const SizedBox(height: 4),
            Tooltip(
              message: result.inputSha256,
              child: Text(
                '입력 SHA-256 ${_shortHash(result.inputSha256)}',
                style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
              ),
            ),
          ],
          if (result.benchmarkConfig.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '설정 ${result.benchmarkConfig.entries.map((entry) => '${entry.key}=${entry.value}').join(' · ')}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
            ),
          ],
          if (result.error?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 7),
            Text(
              result.error!,
              style: TextStyle(fontSize: 10, color: colors.error),
            ),
          ],
          if (result.codeSnippet.isNotEmpty) ...[
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => CodeSnippetDialog.show(context, result),
                icon: const Icon(Icons.code, size: 14),
                label: const Text('코드', style: TextStyle(fontSize: 10)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortHash(String value) =>
      value.length <= 12 ? value : '${value.substring(0, 12)}…';
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 10),
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          TextSpan(
              text: value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
