import 'package:equatable/equatable.dart';

enum ComparisonViewMode {
  grid, // Synchronized Multi-Grid View
  curtainSlider, // 2-Way Before/After Curtain Split Slider
  maskOnly, // Alpha Mask Grayscale View
}

enum BackgroundTheme {
  checkerboard, // Transparent checker pattern
  pureBlack, // #000000 (best for detecting white halos)
  pureWhite, // #FFFFFF (best for detecting cropped edges)
  chromaGreen, // #00FF00 (best for checking translucent alpha transparency)
}

enum EngineRunStatus {
  success,
  unavailable,
  failed;

  static EngineRunStatus fromJson(Object? value) {
    return switch (value?.toString()) {
      'success' => EngineRunStatus.success,
      'unavailable' => EngineRunStatus.unavailable,
      'failed' => EngineRunStatus.failed,
      _ => throw FormatException('알 수 없는 엔진 실행 상태입니다: $value'),
    };
  }
}

enum BenchmarkPhase {
  idle,
  starting,
  running,
  completed,
  completedWithIssues,
  cancelled,
  failed,
}

class EngineResult extends Equatable {
  final String engineId;
  final String name;
  final String framework;
  final String description;
  final double? latencyMs;
  final double? peakMemoryMb;
  final double? peakRssMb;
  final double? baselineRssMb;
  final String outputPath;
  final String maskPath;
  final String resolution;
  final String codeSnippet;
  final EngineRunStatus status;
  final String backendUsed;
  final String modelVersion;
  final String provider;
  final Map<String, double> phaseTimingsMs;
  final String cacheKey;
  final String inputSha256;
  final bool sessionReused;
  final bool rankable;
  final Map<String, Object?> diagnostics;
  final Map<String, Object?> benchmarkConfig;
  final String? error;

  const EngineResult({
    required this.engineId,
    required this.name,
    required this.framework,
    required this.description,
    required this.latencyMs,
    required this.peakMemoryMb,
    this.peakRssMb,
    this.baselineRssMb,
    required this.outputPath,
    required this.maskPath,
    required this.resolution,
    required this.codeSnippet,
    this.status = EngineRunStatus.success,
    this.backendUsed = '',
    this.modelVersion = '',
    this.provider = '',
    this.phaseTimingsMs = const {},
    this.cacheKey = '',
    this.inputSha256 = '',
    this.sessionReused = false,
    bool? rankable,
    this.diagnostics = const {},
    this.benchmarkConfig = const {},
    this.error,
  }) : rankable = rankable ?? status == EngineRunStatus.success;

  factory EngineResult.fromJson(Map<String, dynamic> json) {
    final engineId = json['engine_id']?.toString() ?? '';
    final status = EngineRunStatus.fromJson(json['status']);
    return EngineResult(
      engineId: engineId,
      name: json['name'] ?? '',
      framework: json['framework'] ?? '',
      description: json['description'] ?? '',
      latencyMs: (json['latency_ms'] as num?)?.toDouble(),
      peakMemoryMb: (json['peak_memory_mb'] as num?)?.toDouble(),
      peakRssMb: (json['peak_rss_mb'] as num?)?.toDouble(),
      baselineRssMb: (json['baseline_rss_mb'] as num?)?.toDouble(),
      outputPath: json['output_path'] ?? '',
      maskPath: json['mask_path'] ?? '',
      resolution: json['resolution'] ?? '',
      codeSnippet: json['code_snippet'] ?? '',
      status: status,
      backendUsed: json['backend_used'] ?? '',
      modelVersion: json['model_version'] ?? '',
      provider: json['provider'] ?? '',
      phaseTimingsMs: _parseTimings(json['phase_timings_ms']),
      cacheKey: json['cache_key'] ?? json['output_path'] ?? '',
      inputSha256: json['input_sha256']?.toString() ?? '',
      sessionReused: json['session_reused'] == true,
      rankable: json['rankable'] is bool
          ? json['rankable'] as bool
          : status == EngineRunStatus.success,
      diagnostics: _parseMetadata(json['diagnostics']),
      benchmarkConfig: _parseMetadata(json['benchmark_config']),
      error: json['error']?.toString(),
    );
  }

  static Map<String, double> _parseTimings(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value is num)
          entry.key.toString(): (entry.value as num).toDouble(),
    };
  }

  static Map<String, Object?> _parseMetadata(Object? value) {
    if (value is! Map) return const {};
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key.toString(): entry.value,
    });
  }

  bool get isRankable => rankable && status == EngineRunStatus.success;

  double? get maskCompactness {
    final value = diagnostics['mask_compactness'];
    return value is num ? value.toDouble() : null;
  }

  @override
  List<Object?> get props => [
        engineId,
        name,
        framework,
        description,
        latencyMs,
        peakMemoryMb,
        peakRssMb,
        baselineRssMb,
        outputPath,
        maskPath,
        resolution,
        codeSnippet,
        status,
        backendUsed,
        modelVersion,
        provider,
        phaseTimingsMs,
        cacheKey,
        inputSha256,
        sessionReused,
        rankable,
        diagnostics,
        benchmarkConfig,
        error,
      ];
}

class SampleImageInfo extends Equatable {
  final String id;
  final String title;
  final String subtitle;
  final String challengePoint;
  final String assetPath;

  const SampleImageInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.challengePoint,
    required this.assetPath,
  });

  @override
  List<Object?> get props => [id, title, subtitle, challengePoint, assetPath];
}
