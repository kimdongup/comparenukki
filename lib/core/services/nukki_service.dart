import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/engine_models.dart';

enum BenchmarkCompletionStatus {
  running,
  success,
  partial,
  failed;

  static BenchmarkCompletionStatus fromProtocol(Object? value) =>
      switch (value?.toString()) {
        'success' => BenchmarkCompletionStatus.success,
        'partial' => BenchmarkCompletionStatus.partial,
        'failed' => BenchmarkCompletionStatus.failed,
        _ => BenchmarkCompletionStatus.failed,
      };
}

class BenchmarkUpdate {
  final String requestId;
  final EngineResult? result;
  final String? activeEngineId;
  final int completed;
  final int total;
  final bool isComplete;
  final BenchmarkCompletionStatus completionStatus;

  const BenchmarkUpdate({
    required this.requestId,
    this.result,
    this.activeEngineId,
    required this.completed,
    required this.total,
    this.isComplete = false,
    this.completionStatus = BenchmarkCompletionStatus.running,
  });

  double get progress => total == 0 ? 0 : (completed / total).clamp(0, 1);
}

class BenchmarkProcessException implements Exception {
  final String message;

  const BenchmarkProcessException(this.message);

  @override
  String toString() => message;
}

class NukkiService {
  static const List<SampleImageInfo> sampleImages = [
    SampleImageInfo(
      id: 'sample1_pencil_case',
      title: '청록색 펜슬 케이스',
      subtitle: '반투명 플라스틱 뚜껑 & 흰색 하단 베이스',
      challengePoint: '상단 반투명 뚜껑의 투과율 보존 vs 흰색 바닥과 배경의 경계 분리',
      assetPath: 'assets/samples/sample1_pencil_case.jpg',
    ),
    SampleImageInfo(
      id: 'sample2_colored_pencils',
      title: '크레욜라 24색 색연필 & 펜',
      subtitle: '극세 보라색 곡선 낙서 선 & 낱자루',
      challengePoint: '오른쪽 보라색 연필 상단의 극도로 얇은 곡선 라인 지워짐 없이 보존',
      assetPath: 'assets/samples/sample2_colored_pencils.jpg',
    ),
    SampleImageInfo(
      id: 'sample3_erasers',
      title: 'PaperMate 지우개 3입 팩',
      subtitle: '투명 플라스틱(블리스터) 패키지 & 지우개',
      challengePoint: '지우개를 감싸고 있는 투명 플라스틱의 모서리 반사광 및 테두리 유지',
      assetPath: 'assets/samples/sample3_erasers.jpg',
    ),
    SampleImageInfo(
      id: 'sample4_crayons',
      title: '크레욜라 24색 크레용 팩',
      subtitle: '이커머스 제품 박스 & 하단 접지면 그림자',
      challengePoint: '바닥 그림자를 과도하게 남기지 않고 제품 하단 접지면을 깔끔하게 절단',
      assetPath: 'assets/samples/sample4_crayons.jpg',
    ),
  ];

  Process? _worker;
  Future<void>? _workerStart;
  Future<void>? _workerStop;
  Future<void>? _disposeOperation;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamController<BenchmarkUpdate>? _activeController;
  Timer? _timeoutTimer;
  String? _activeRequestId;
  int _completedCount = 0;
  int _totalCount = 0;
  int _requestSequence = 0;
  int _launchGeneration = 0;
  bool _disposed = false;
  bool _didSweepStaleOutputs = false;
  final List<String> _ownedOutputDirectories = [];
  Future<void> _outputMaintenance = Future<void>.value();
  final Set<Future<void>> _benchmarkLaunches = {};

  static bool get supportsLocalWorker =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  String _findPythonExecutable() {
    final configured = Platform.environment['COMPARENUKKI_PYTHON'];
    if (configured?.trim().isNotEmpty == true) {
      final executable = configured!.trim();
      if (!executable.contains(Platform.pathSeparator) ||
          File(executable).existsSync()) {
        return executable;
      }
      throw BenchmarkProcessException(
        'COMPARENUKKI_PYTHON 실행 파일을 찾을 수 없습니다: $executable',
      );
    }

    final virtualEnvironment = Platform.environment['VIRTUAL_ENV'];
    final userHome = Platform.environment['HOME'];
    final candidates = [
      if (virtualEnvironment != null && Platform.isWindows)
        '$virtualEnvironment\\Scripts\\python.exe',
      if (virtualEnvironment != null && !Platform.isWindows)
        '$virtualEnvironment/bin/python3',
      if (!Platform.isWindows && userHome != null)
        '$userHome/.pyenv/shims/python3',
      if (!Platform.isWindows) '/usr/local/bin/python3',
      if (!Platform.isWindows) '/opt/homebrew/bin/python3',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return Platform.isWindows ? 'python' : 'python3';
  }

  Stream<BenchmarkUpdate> runBenchmark({
    required String imagePath,
    String engineId = 'all',
    Duration timeout = const Duration(minutes: 3),
  }) {
    final controller = StreamController<BenchmarkUpdate>();
    final launchGeneration = ++_launchGeneration;
    final launch = _startBenchmark(
      controller: controller,
      imagePath: imagePath,
      engineId: engineId,
      timeout: timeout,
      launchGeneration: launchGeneration,
    );
    late final Future<void> trackedLaunch;
    trackedLaunch = launch.then<void>(
      (_) {
        _benchmarkLaunches.remove(trackedLaunch);
      },
      onError: (Object error, StackTrace stackTrace) {
        _benchmarkLaunches.remove(trackedLaunch);
        debugPrint('[CompareNukki launch] $error\n$stackTrace');
      },
    );
    _benchmarkLaunches.add(trackedLaunch);
    unawaited(trackedLaunch);
    return controller.stream;
  }

  Future<void> _startBenchmark({
    required StreamController<BenchmarkUpdate> controller,
    required String imagePath,
    required String engineId,
    required Duration timeout,
    required int launchGeneration,
  }) async {
    if (_disposed) {
      controller.addError(
        const BenchmarkProcessException('벤치마크 서비스가 이미 종료되었습니다.'),
      );
      await controller.close();
      return;
    }

    try {
      if (_activeController != null) {
        await _cancelActiveBenchmarkInternal();
      }
      await _ensureWorker();
      if (launchGeneration != _launchGeneration) {
        await controller.close();
        return;
      }
      final worker = _worker;
      if (worker == null) {
        throw const BenchmarkProcessException('Python 워커를 시작하지 못했습니다.');
      }

      final requestId =
          '${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';
      final outputRoot = await _createOutputDirectory(requestId);
      if (launchGeneration != _launchGeneration) {
        await controller.close();
        return;
      }
      final resolvedImagePath = await _resolveImagePath(imagePath, outputRoot);
      if (launchGeneration != _launchGeneration) {
        await controller.close();
        return;
      }

      _activeController = controller;
      _activeRequestId = requestId;
      _completedCount = 0;
      _totalCount = engineId == 'all' ? 0 : 1;
      _timeoutTimer = Timer(timeout, () {
        unawaited(
          _failActiveRequest(
            BenchmarkProcessException(
              '벤치마크가 ${timeout.inSeconds}초 제한을 초과해 워커를 종료했습니다.',
            ),
          ),
        );
      });

      controller.add(
        BenchmarkUpdate(
          requestId: requestId,
          completed: 0,
          total: _totalCount,
        ),
      );

      worker.stdin.writeln(
        jsonEncode({
          'command': 'run',
          'request_id': requestId,
          'image': resolvedImagePath,
          'engine': engineId,
          'output_dir': outputRoot.path,
        }),
      );
      await worker.stdin.flush();
    } catch (error, stackTrace) {
      if (identical(_activeController, controller)) {
        await _failActiveRequest(error, stackTrace: stackTrace);
      } else if (!controller.isClosed) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
    }
  }

  Future<void> _ensureWorker() async {
    final stopping = _workerStop;
    if (stopping != null) await stopping;
    if (_disposed) {
      throw const BenchmarkProcessException('벤치마크 서비스가 이미 종료되었습니다.');
    }
    if (_worker != null) return;
    final existingStart = _workerStart;
    if (existingStart != null) return existingStart;

    final start = _startWorker();
    _workerStart = start;
    try {
      await start;
    } finally {
      if (identical(_workerStart, start)) _workerStart = null;
    }
  }

  Future<void> _startWorker() async {
    if (!supportsLocalWorker) {
      throw const BenchmarkProcessException(
        '로컬 Python 벤치마크는 데스크톱 플랫폼에서만 지원됩니다.',
      );
    }
    final currentDirectory = Directory.current.path;
    final backendDirectory = _findBackendDirectory(currentDirectory);
    final workerPath = '$backendDirectory/engine_worker.py';

    final process = await Process.start(
      _findPythonExecutable(),
      [workerPath],
      workingDirectory: backendDirectory,
      mode: ProcessStartMode.normal,
    );
    _worker = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleWorkerLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => debugPrint('[CompareNukki worker] $line'));
    unawaited(
      process.exitCode.then((exitCode) => _handleWorkerExit(process, exitCode)),
    );
  }

  void _handleWorkerLine(String line) {
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        unawaited(
          _failActiveRequest(
            const BenchmarkProcessException(
              'Python 워커 프로토콜이 JSON 객체가 아닙니다.',
            ),
          ),
        );
        return;
      }
      message = decoded;
    } on FormatException {
      debugPrint('[CompareNukki worker stdout] $line');
      if (_activeController != null) {
        unawaited(
          _failActiveRequest(
            const BenchmarkProcessException(
              'Python 워커가 올바르지 않은 JSON 응답을 반환했습니다.',
            ),
          ),
        );
      }
      return;
    }

    final controller = _activeController;
    final requestId = message['request_id']?.toString();
    if (controller == null ||
        controller.isClosed ||
        requestId != _activeRequestId) {
      return;
    }

    switch (message['type']) {
      case 'engine_started':
        final reportedTotal = message['total'];
        if (reportedTotal is num && reportedTotal > 0) {
          _totalCount = reportedTotal.toInt();
        }
        controller.add(
          BenchmarkUpdate(
            requestId: requestId!,
            activeEngineId: message['engine_id']?.toString(),
            completed: _completedCount,
            total: _totalCount,
          ),
        );
        break;
      case 'engine_result':
        final rawResult = message['result'];
        if (rawResult is! Map) {
          unawaited(
            _failActiveRequest(
              const BenchmarkProcessException(
                'Python 워커가 올바르지 않은 엔진 결과를 반환했습니다.',
              ),
            ),
          );
          return;
        }
        EngineResult result;
        try {
          result = EngineResult.fromJson(Map<String, dynamic>.from(rawResult));
        } catch (error) {
          unawaited(
            _failActiveRequest(
              BenchmarkProcessException('엔진 결과 형식을 해석하지 못했습니다: $error'),
            ),
          );
          return;
        }
        _completedCount++;
        controller.add(
          BenchmarkUpdate(
            requestId: requestId!,
            result: result,
            activeEngineId: result.engineId,
            completed: _completedCount,
            total: _totalCount,
          ),
        );
        break;
      case 'complete':
        controller.add(
          BenchmarkUpdate(
            requestId: requestId!,
            completed: _completedCount,
            total: _totalCount,
            isComplete: true,
            completionStatus: BenchmarkCompletionStatus.fromProtocol(
              message['status'],
            ),
          ),
        );
        unawaited(controller.close());
        _clearActiveRequest();
        break;
      case 'error':
        unawaited(
          _failActiveRequest(
            BenchmarkProcessException(
              message['error']?.toString() ?? 'Python 워커 오류',
            ),
          ),
        );
        break;
    }
  }

  Future<void> _handleWorkerExit(Process process, int exitCode) async {
    if (!identical(_worker, process)) return;
    final stdoutSubscription = _stdoutSubscription;
    final stderrSubscription = _stderrSubscription;
    final controller = _activeController;
    _worker = null;
    _stdoutSubscription = null;
    _stderrSubscription = null;
    if (controller != null) _clearActiveRequest();

    try {
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
    } catch (error) {
      debugPrint('[CompareNukki worker] 종료 스트림 정리 실패: $error');
    }

    if (controller != null && !controller.isClosed) {
      try {
        controller.addError(
          BenchmarkProcessException(
            'Python 워커가 예기치 않게 종료되었습니다. (exit code $exitCode)',
          ),
        );
        await controller.close();
      } catch (error) {
        debugPrint('[CompareNukki worker] 종료 오류 전달 실패: $error');
      }
    }
  }

  Future<void> _failActiveRequest(
    Object error, {
    StackTrace? stackTrace,
  }) async {
    final controller = _activeController;
    _clearActiveRequest();
    final stopping = _stopWorker();
    try {
      if (controller != null && !controller.isClosed) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
    } finally {
      await stopping;
    }
  }

  Future<void> cancelActiveBenchmark() async {
    _launchGeneration++;
    await _cancelActiveBenchmarkInternal();
  }

  Future<void> _cancelActiveBenchmarkInternal() async {
    final controller = _activeController;
    _clearActiveRequest();
    if (controller != null) {
      final stopping = _stopWorker();
      try {
        if (!controller.isClosed) await controller.close();
      } finally {
        await stopping;
      }
    }
  }

  void _clearActiveRequest() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _activeController = null;
    _activeRequestId = null;
    _completedCount = 0;
    _totalCount = 0;
  }

  Future<void> _stopWorker() {
    final existingStop = _workerStop;
    if (existingStop != null) return existingStop;
    final completer = Completer<void>();
    _workerStop = completer.future;
    unawaited(_performWorkerStop(completer));
    return completer.future;
  }

  Future<void> _performWorkerStop(Completer<void> completer) async {
    try {
      final starting = _workerStart;
      if (starting != null) {
        try {
          await starting;
        } catch (_) {
          // A failed start has no process to terminate.
        }
      }

      final process = _worker;
      final stdoutSubscription = _stdoutSubscription;
      final stderrSubscription = _stderrSubscription;
      _worker = null;
      _stdoutSubscription = null;
      _stderrSubscription = null;

      if (process != null) {
        try {
          await process.stdin.close();
        } catch (_) {
          // The worker may already have closed stdin while exiting.
        }
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
      }
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _workerStop = null;
    }
  }

  Future<String> _resolveImagePath(
    String imagePath,
    Directory requestDirectory,
  ) async {
    final file = File(imagePath);
    if (file.isAbsolute && await file.exists()) return file.path;
    final repositoryFile = File('${Directory.current.path}/$imagePath');
    if (await repositoryFile.exists()) return repositoryFile.absolute.path;

    if (imagePath.startsWith('assets/')) {
      try {
        final data = await rootBundle.load(imagePath);
        final extension =
            imagePath.contains('.') ? '.${imagePath.split('.').last}' : '.img';
        final materialized = File(
          '${requestDirectory.path}/benchmark_input$extension',
        );
        await materialized.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        return materialized.path;
      } catch (error) {
        throw BenchmarkProcessException('앱 자산 이미지를 준비하지 못했습니다: $error');
      }
    }
    throw BenchmarkProcessException('입력 이미지 파일을 찾을 수 없습니다: $imagePath');
  }

  Future<Directory> _createOutputDirectory(String requestId) async {
    final previousMaintenance = _outputMaintenance;
    final turn = Completer<void>();
    _outputMaintenance = turn.future;
    try {
      await previousMaintenance;
      Directory baseDirectory;
      try {
        baseDirectory = await getTemporaryDirectory();
      } catch (_) {
        baseDirectory = Directory.systemTemp;
      }
      final outputRoot = Directory(
        '${baseDirectory.path}/comparenukki/outputs',
      );
      await outputRoot.create(recursive: true);
      if (!_didSweepStaleOutputs) {
        _didSweepStaleOutputs = true;
        await _sweepStaleOutputDirectories(outputRoot);
      }

      final directory = await Directory(
        '${outputRoot.path}/$requestId',
      ).create(recursive: true);
      _ownedOutputDirectories.add(directory.path);
      while (_ownedOutputDirectories.length > 3) {
        await _deleteOutputDirectory(_ownedOutputDirectories.removeAt(0));
      }
      return directory;
    } finally {
      turn.complete();
    }
  }

  String _findBackendDirectory(String currentDirectory) {
    final configured = Platform.environment['COMPARENUKKI_BACKEND_DIR'];
    if (configured?.trim().isNotEmpty == true) {
      final directory = Directory(configured!.trim()).absolute.path;
      if (File('$directory/engine_worker.py').existsSync()) return directory;
      throw BenchmarkProcessException(
        'COMPARENUKKI_BACKEND_DIR에 Python 워커가 없습니다: $directory',
      );
    }

    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$currentDirectory/backend',
      '$executableDirectory/data/flutter_assets/backend',
      '$executableDirectory/../Frameworks/App.framework/Resources/'
          'flutter_assets/backend',
    ];
    for (final candidate in candidates) {
      final directory = Directory(candidate).absolute.path;
      if (File('$directory/engine_worker.py').existsSync()) return directory;
    }
    throw BenchmarkProcessException(
      'Python 워커를 찾을 수 없습니다. COMPARENUKKI_BACKEND_DIR을 설정하세요.',
    );
  }

  Future<void> _sweepStaleOutputDirectories(Directory outputRoot) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    try {
      await for (final entity in outputRoot.list(followLinks: false)) {
        if (entity is! Directory ||
            _ownedOutputDirectories.contains(entity.path)) {
          continue;
        }
        final modified = (await entity.stat()).modified;
        if (modified.isBefore(cutoff)) {
          await _deleteOutputDirectory(entity.path);
        }
      }
    } on FileSystemException catch (error) {
      debugPrint('[CompareNukki outputs] 오래된 결과 정리 실패: $error');
    }
  }

  Future<void> _deleteOutputDirectory(String path) async {
    try {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException catch (error) {
      debugPrint('[CompareNukki outputs] 임시 결과 정리 실패: $error');
    }
  }

  Future<void> _deleteOwnedOutputDirectories() async {
    final paths = List<String>.of(_ownedOutputDirectories);
    _ownedOutputDirectories.clear();
    for (final path in paths) {
      await _deleteOutputDirectory(path);
    }
  }

  Future<void> dispose() {
    final existing = _disposeOperation;
    if (existing != null) return existing;
    final operation = _performDispose();
    _disposeOperation = operation;
    return operation;
  }

  Future<void> _performDispose() async {
    _disposed = true;
    final starting = _workerStart;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        // Startup failure is already surfaced to the active request.
      }
    }
    try {
      await cancelActiveBenchmark();
    } finally {
      try {
        try {
          await _stopWorker();
        } finally {
          final launches = List<Future<void>>.of(_benchmarkLaunches);
          if (launches.isNotEmpty) await Future.wait(launches);
        }
      } finally {
        await _outputMaintenance;
        await _deleteOwnedOutputDirectories();
      }
    }
  }
}
