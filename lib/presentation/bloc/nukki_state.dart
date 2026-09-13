import 'package:equatable/equatable.dart';
import '../../core/models/engine_models.dart';

const _notProvided = Object();

class NukkiState extends Equatable {
  final SampleImageInfo currentImage;
  final ComparisonViewMode viewMode;
  final BackgroundTheme bgTheme;
  final Map<String, EngineResult> results;
  final double curtainRatio;
  final String curtainEngineA;
  final String curtainEngineB;
  final double progress;
  final String? activeEngineId;
  final BenchmarkPhase benchmarkPhase;
  final String? errorMessage;
  final bool isLocalWorkerSupported;
  final List<SampleImageInfo> availableSamples;

  const NukkiState({
    required this.currentImage,
    required this.viewMode,
    required this.bgTheme,
    required this.results,
    this.curtainRatio = 0.5,
    this.curtainEngineA = 'original',
    this.curtainEngineB = 'birefnet',
    this.progress = 0,
    this.activeEngineId,
    this.benchmarkPhase = BenchmarkPhase.idle,
    this.errorMessage,
    this.isLocalWorkerSupported = true,
    this.availableSamples = const [],
  });

  bool get isLoading =>
      benchmarkPhase == BenchmarkPhase.starting ||
      benchmarkPhase == BenchmarkPhase.running;

  NukkiState copyWith({
    SampleImageInfo? currentImage,
    ComparisonViewMode? viewMode,
    BackgroundTheme? bgTheme,
    Map<String, EngineResult>? results,
    double? curtainRatio,
    String? curtainEngineA,
    String? curtainEngineB,
    double? progress,
    Object? activeEngineId = _notProvided,
    BenchmarkPhase? benchmarkPhase,
    Object? errorMessage = _notProvided,
    bool? isLocalWorkerSupported,
    List<SampleImageInfo>? availableSamples,
  }) {
    return NukkiState(
      currentImage: currentImage ?? this.currentImage,
      viewMode: viewMode ?? this.viewMode,
      bgTheme: bgTheme ?? this.bgTheme,
      results: results ?? this.results,
      curtainRatio: curtainRatio ?? this.curtainRatio,
      curtainEngineA: curtainEngineA ?? this.curtainEngineA,
      curtainEngineB: curtainEngineB ?? this.curtainEngineB,
      progress: progress ?? this.progress,
      activeEngineId: identical(activeEngineId, _notProvided)
          ? this.activeEngineId
          : activeEngineId as String?,
      benchmarkPhase: benchmarkPhase ?? this.benchmarkPhase,
      errorMessage: identical(errorMessage, _notProvided)
          ? this.errorMessage
          : errorMessage as String?,
      isLocalWorkerSupported:
          isLocalWorkerSupported ?? this.isLocalWorkerSupported,
      availableSamples: availableSamples ?? this.availableSamples,
    );
  }

  @override
  List<Object?> get props => [
        currentImage,
        viewMode,
        bgTheme,
        results,
        curtainRatio,
        curtainEngineA,
        curtainEngineB,
        progress,
        activeEngineId,
        benchmarkPhase,
        errorMessage,
        isLocalWorkerSupported,
        availableSamples,
      ];
}
