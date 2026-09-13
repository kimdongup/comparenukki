import 'dart:async';

import 'package:comparenukki/core/models/engine_models.dart';
import 'package:comparenukki/core/services/nukki_service.dart';
import 'package:comparenukki/presentation/bloc/nukki_bloc.dart';
import 'package:comparenukki/presentation/bloc/nukki_event.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingNukkiService extends NukkiService {
  RecordingNukkiService({
    this.completionStatus = BenchmarkCompletionStatus.success,
  });

  final BenchmarkCompletionStatus completionStatus;
  int runCount = 0;
  int cancelCount = 0;

  @override
  Stream<BenchmarkUpdate> runBenchmark({
    required String imagePath,
    String engineId = 'all',
    Duration timeout = const Duration(minutes: 3),
  }) {
    runCount++;
    const requestId = 'test-request';
    const result = EngineResult(
      engineId: 'grabcut',
      name: 'OpenCV GrabCut',
      framework: 'OpenCV',
      description: 'test',
      latencyMs: 12,
      peakMemoryMb: 24,
      outputPath: '/tmp/test-result.png',
      maskPath: '/tmp/test-mask.png',
      resolution: '32x32',
      codeSnippet: '',
      status: EngineRunStatus.success,
      backendUsed: 'opencv-grabcut',
      provider: 'CPU',
      cacheKey: 'test-cache-key',
    );
    return Stream.fromIterable([
      const BenchmarkUpdate(requestId: requestId, completed: 0, total: 1),
      const BenchmarkUpdate(
        requestId: requestId,
        result: result,
        activeEngineId: 'grabcut',
        completed: 1,
        total: 1,
      ),
      BenchmarkUpdate(
        requestId: requestId,
        completed: 1,
        total: 1,
        isComplete: true,
        completionStatus: completionStatus,
      ),
    ]);
  }

  @override
  Future<void> cancelActiveBenchmark() async {
    cancelCount++;
  }

  @override
  Future<void> dispose() async {}
}

class FailingCancelNukkiService extends RecordingNukkiService {
  @override
  Future<void> cancelActiveBenchmark() =>
      Future<void>.error(StateError('stop failed'));
}

void main() {
  test('missing metrics stay null and unavailable results are not rankable',
      () {
    final result = EngineResult.fromJson(const {
      'engine_id': 'mobilesam',
      'name': 'MobileSAM',
      'status': 'unavailable',
      'error': 'checkpoint missing',
    });

    expect(result.status, EngineRunStatus.unavailable);
    expect(result.latencyMs, isNull);
    expect(result.peakMemoryMb, isNull);
    expect(result.isRankable, isFalse);
  });

  test('worker provenance, diagnostics and rankability are preserved', () {
    final result = EngineResult.fromJson(const {
      'engine_id': 'requested',
      'name': 'Engine',
      'status': 'success',
      'rankable': false,
      'latency_ms': 1.0,
      'input_sha256': 'abc123',
      'diagnostics': {'mask_compactness': 0.42},
      'benchmark_config': {'threads': 2},
    });

    expect(result.inputSha256, 'abc123');
    expect(result.maskCompactness, 0.42);
    expect(result.benchmarkConfig['threads'], 2);
    expect(result.isRankable, isFalse);
  });

  test('rank permission is independent from an individual nullable metric', () {
    final result = EngineResult.fromJson(const {
      'engine_id': 'memory-only',
      'name': 'Memory only',
      'status': 'success',
      'rankable': true,
      'latency_ms': null,
      'peak_memory_mb': 10,
    });

    expect(result.isRankable, isTrue);
    expect(result.latencyMs, isNull);
    expect(result.peakMemoryMb, 10);
  });

  test('unknown worker result status is rejected as malformed', () {
    expect(
      () => EngineResult.fromJson(const {
        'engine_id': 'unknown',
        'status': 'completed',
      }),
      throwsFormatException,
    );
  });

  test('startup and image selection do not execute a benchmark', () async {
    final service = RecordingNukkiService();
    final bloc = NukkiBloc(nukkiService: service);

    expect(service.runCount, 0);
    expect(bloc.state.currentImage, NukkiService.sampleImages.first);

    final selected = bloc.stream.firstWhere(
      (state) => state.currentImage == NukkiService.sampleImages.last,
    );
    bloc.add(SelectSampleImageEvent(NukkiService.sampleImages.last));
    await selected.timeout(const Duration(seconds: 1));
    expect(service.runCount, 0);
    expect(bloc.state.currentImage, NukkiService.sampleImages.last);
    expect(bloc.state.benchmarkPhase, BenchmarkPhase.idle);

    await bloc.close();
  });

  test('explicit run streams results and completes progress', () async {
    final service = RecordingNukkiService();
    final bloc = NukkiBloc(nukkiService: service);
    final completed = bloc.stream.firstWhere(
      (state) => state.benchmarkPhase == BenchmarkPhase.completed,
    );

    bloc.add(const RunBenchmarkEvent(engineId: 'grabcut'));
    final state = await completed.timeout(const Duration(seconds: 1));

    expect(service.runCount, 1);
    expect(state.progress, 1);
    expect(state.results['grabcut']?.latencyMs, 12);
    expect(state.isLoading, isFalse);

    await bloc.close();
  });

  test('partial worker completion is surfaced as completed with issues',
      () async {
    final service = RecordingNukkiService(
      completionStatus: BenchmarkCompletionStatus.partial,
    );
    final bloc = NukkiBloc(nukkiService: service);
    final completed = bloc.stream.firstWhere(
      (state) => state.benchmarkPhase == BenchmarkPhase.completedWithIssues,
    );

    bloc.add(const RunBenchmarkEvent(engineId: 'grabcut'));
    final state = await completed.timeout(const Duration(seconds: 1));

    expect(state.results, contains('grabcut'));
    expect(state.isLoading, isFalse);
    await bloc.close();
  });

  test('failed worker completion is not reported as success', () async {
    final service = RecordingNukkiService(
      completionStatus: BenchmarkCompletionStatus.failed,
    );
    final bloc = NukkiBloc(nukkiService: service);
    final failed = bloc.stream.firstWhere(
      (state) => state.benchmarkPhase == BenchmarkPhase.failed,
    );

    bloc.add(const RunBenchmarkEvent(engineId: 'grabcut'));
    final state = await failed.timeout(const Duration(seconds: 1));

    expect(state.isLoading, isFalse);
    expect(state.errorMessage, isNotNull);
    await bloc.close();
  });

  test('cancel after completion does not overwrite the completed phase',
      () async {
    final service = RecordingNukkiService();
    final bloc = NukkiBloc(nukkiService: service);
    final completed = bloc.stream.firstWhere(
      (state) => state.benchmarkPhase == BenchmarkPhase.completed,
    );

    bloc.add(const RunBenchmarkEvent(engineId: 'grabcut'));
    await completed.timeout(const Duration(seconds: 1));
    bloc.add(const CancelBenchmarkEvent());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(bloc.state.benchmarkPhase, BenchmarkPhase.completed);
    await bloc.close();
  });

  test('image replacement cancellation failure leaves a non-running state',
      () async {
    final service = FailingCancelNukkiService();
    final bloc = NukkiBloc(nukkiService: service);
    final failed = bloc.stream.firstWhere(
      (state) => state.benchmarkPhase == BenchmarkPhase.failed,
    );

    bloc.add(SelectSampleImageEvent(NukkiService.sampleImages.last));
    final state = await failed.timeout(const Duration(seconds: 1));

    expect(state.currentImage, NukkiService.sampleImages.first);
    expect(state.isLoading, isFalse);
    expect(state.errorMessage, contains('중단하지 못했습니다'));
    await expectLater(bloc.close(), throwsStateError);
  });
}
