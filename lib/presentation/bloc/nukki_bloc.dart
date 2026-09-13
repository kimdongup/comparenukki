import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/models/engine_models.dart';
import '../../core/services/nukki_service.dart';
import 'nukki_event.dart';
import 'nukki_state.dart';

class NukkiBloc extends Bloc<NukkiEvent, NukkiState> {
  final NukkiService nukkiService;
  final bool _ownsService;
  int _requestGeneration = 0;

  NukkiBloc({required this.nukkiService, bool ownsService = false})
      : _ownsService = ownsService,
        super(NukkiState(
          currentImage: NukkiService.sampleImages.first,
          viewMode: ComparisonViewMode.grid,
          bgTheme: BackgroundTheme.checkerboard,
          results: const {},
          isLocalWorkerSupported: NukkiService.supportsLocalWorker,
          availableSamples: NukkiService.sampleImages,
        )) {
    on<SelectSampleImageEvent>(_onSelectSampleImage);
    on<UploadCustomImageEvent>(_onUploadCustomImage);
    on<ChangeViewModeEvent>(_onChangeViewMode);
    on<ChangeBackgroundThemeEvent>(_onChangeBackgroundTheme);
    on<SetCurtainSliderRatioEvent>(_onSetCurtainSliderRatio);
    on<SetCurtainEnginesEvent>(_onSetCurtainEngines);
    on<RunBenchmarkEvent>(_onRunBenchmark);
    on<CancelBenchmarkEvent>(_onCancelBenchmark);
  }

  factory NukkiBloc.owned() => NukkiBloc(
        nukkiService: NukkiService(),
        ownsService: true,
      );

  Future<void> _onSelectSampleImage(
    SelectSampleImageEvent event,
    Emitter<NukkiState> emit,
  ) =>
      _replaceImage(event.sample, emit);

  Future<void> _onUploadCustomImage(
    UploadCustomImageEvent event,
    Emitter<NukkiState> emit,
  ) async {
    final customSample = SampleImageInfo(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      title: '사용자 업로드 이미지',
      subtitle: event.filePath.replaceAll('\\', '/').split('/').last,
      challengePoint: '사용자 지정 커스텀 이미지 배경 제거 비교',
      assetPath: event.filePath,
    );

    await _replaceImage(customSample, emit);
  }

  Future<void> _replaceImage(
    SampleImageInfo image,
    Emitter<NukkiState> emit,
  ) async {
    final generation = ++_requestGeneration;
    final cancelled = await _cancelForTransition(
      generation,
      emit,
      failureContext: '이미지를 변경하기 전에 실행 중인 작업을 중단하지 못했습니다.',
    );
    if (!cancelled) return;
    emit(state.copyWith(
      currentImage: image,
      results: const {},
      progress: 0,
      activeEngineId: null,
      benchmarkPhase: BenchmarkPhase.idle,
      errorMessage: null,
    ));
  }

  void _onChangeViewMode(
    ChangeViewModeEvent event,
    Emitter<NukkiState> emit,
  ) {
    emit(state.copyWith(viewMode: event.mode));
  }

  void _onChangeBackgroundTheme(
    ChangeBackgroundThemeEvent event,
    Emitter<NukkiState> emit,
  ) {
    emit(state.copyWith(bgTheme: event.theme));
  }

  void _onSetCurtainSliderRatio(
    SetCurtainSliderRatioEvent event,
    Emitter<NukkiState> emit,
  ) {
    emit(state.copyWith(curtainRatio: event.ratio.clamp(0.0, 1.0)));
  }

  void _onSetCurtainEngines(
    SetCurtainEnginesEvent event,
    Emitter<NukkiState> emit,
  ) {
    emit(state.copyWith(
      curtainEngineA: event.engineA,
      curtainEngineB: event.engineB,
    ));
  }

  Future<void> _onRunBenchmark(
    RunBenchmarkEvent event,
    Emitter<NukkiState> emit,
  ) async {
    final generation = ++_requestGeneration;

    emit(state.copyWith(
      results: const {},
      progress: 0,
      activeEngineId: null,
      benchmarkPhase: BenchmarkPhase.starting,
      errorMessage: null,
    ));

    try {
      var receivedCompletion = false;
      await for (final update in nukkiService.runBenchmark(
        imagePath: state.currentImage.assetPath,
        engineId: event.engineId,
      )) {
        if (generation != _requestGeneration) return;

        final result = update.result;
        final nextResults = result == null
            ? state.results
            : Map<String, EngineResult>.unmodifiable({
                ...state.results,
                result.engineId: result,
              });

        final completionPhase = update.isComplete
            ? _phaseForCompletionStatus(update.completionStatus)
            : BenchmarkPhase.running;
        receivedCompletion = receivedCompletion || update.isComplete;

        emit(state.copyWith(
          results: nextResults,
          progress: update.progress,
          activeEngineId: update.isComplete ? null : update.activeEngineId,
          benchmarkPhase: completionPhase,
          errorMessage: completionPhase == BenchmarkPhase.failed
              ? '실행 가능한 엔진 결과가 없습니다. 각 엔진의 오류 내용을 확인하세요.'
              : null,
        ));
      }

      if (generation != _requestGeneration) return;
      if (!receivedCompletion) {
        throw const BenchmarkProcessException(
          'Python 워커가 완료 상태 없이 응답을 종료했습니다.',
        );
      }
    } catch (e) {
      if (generation != _requestGeneration) return;
      emit(state.copyWith(
        activeEngineId: null,
        benchmarkPhase: BenchmarkPhase.failed,
        errorMessage: '벤치마크 실행 실패: $e',
      ));
    }
  }

  BenchmarkPhase _phaseForCompletionStatus(
    BenchmarkCompletionStatus status,
  ) =>
      switch (status) {
        BenchmarkCompletionStatus.success => BenchmarkPhase.completed,
        BenchmarkCompletionStatus.partial => BenchmarkPhase.completedWithIssues,
        BenchmarkCompletionStatus.running ||
        BenchmarkCompletionStatus.failed =>
          BenchmarkPhase.failed,
      };

  Future<void> _onCancelBenchmark(
    CancelBenchmarkEvent event,
    Emitter<NukkiState> emit,
  ) async {
    if (!state.isLoading) return;
    final generation = ++_requestGeneration;
    final cancelled = await _cancelForTransition(
      generation,
      emit,
      failureContext: '실행 중인 작업을 취소하지 못했습니다.',
    );
    if (!cancelled) return;
    emit(state.copyWith(
      activeEngineId: null,
      benchmarkPhase: BenchmarkPhase.cancelled,
      errorMessage: null,
    ));
  }

  Future<bool> _cancelForTransition(
    int generation,
    Emitter<NukkiState> emit, {
    required String failureContext,
  }) async {
    try {
      await nukkiService.cancelActiveBenchmark();
    } catch (error) {
      if (generation == _requestGeneration) {
        emit(state.copyWith(
          activeEngineId: null,
          benchmarkPhase: BenchmarkPhase.failed,
          errorMessage: '$failureContext $error',
        ));
      }
      return false;
    }
    return generation == _requestGeneration;
  }

  @override
  Future<void> close() async {
    _requestGeneration++;
    final blocClose = super.close();
    try {
      if (_ownsService) {
        await nukkiService.dispose();
      } else {
        await nukkiService.cancelActiveBenchmark();
      }
    } finally {
      await blocClose;
    }
  }
}
