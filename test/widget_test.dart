import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comparenukki/core/models/engine_models.dart';
import 'package:comparenukki/core/services/nukki_service.dart';
import 'package:comparenukki/presentation/bloc/nukki_bloc.dart';
import 'package:comparenukki/presentation/screens/compare_dashboard_screen.dart';
import 'package:comparenukki/presentation/widgets/metrics_table_view.dart';

class FakeNukkiService extends NukkiService {
  int runCount = 0;

  @override
  Stream<BenchmarkUpdate> runBenchmark({
    required String imagePath,
    String engineId = 'all',
    Duration timeout = const Duration(minutes: 3),
  }) {
    runCount++;
    return const Stream.empty();
  }

  @override
  Future<void> cancelActiveBenchmark() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('wide dashboard renders three role-based areas without auto run',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeService = FakeNukkiService();
    final bloc = NukkiBloc(nukkiService: fakeService);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const CompareDashboardScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('🖼️ CompareNukki'), findsOneWidget);
    expect(find.text('사진 추가'), findsOneWidget);
    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('지표 비교'), findsOneWidget);
    expect(find.text('동기화 그리드'), findsOneWidget);
    expect(find.text('2단 슬라이더'), findsOneWidget);
    expect(find.text('비교할 결과가 아직 없습니다'), findsOneWidget);
    expect(fakeService.runCount, 0);

    await tester.tap(find.text('알파 마스크'));
    await tester.pumpAndSettle();
    expect(find.text('마스크 배경 고정'), findsOneWidget);
  });

  testWidgets('compact dashboard exposes the same areas as navigation tabs',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeService = FakeNukkiService();
    final bloc = NukkiBloc(nukkiService: fakeService);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const CompareDashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('비교할 결과가 아직 없습니다'), findsOneWidget);

    await tester.tap(find.text('사진 추가'));
    await tester.pumpAndSettle();
    expect(find.text('내 이미지 추가'), findsOneWidget);

    await tester.tap(find.text('지표 비교').last);
    await tester.pumpAndSettle();
    expect(find.text('비교할 지표가 없습니다'), findsOneWidget);
    expect(fakeService.runCount, 0);
  });

  testWidgets('compact landscape keeps empty and curtain compare scroll-safe',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(667, 375);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeService = FakeNukkiService();
    final bloc = NukkiBloc(nukkiService: fakeService);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const CompareDashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('비교할 결과가 아직 없습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('2단 슬라이더'));
    await tester.pumpAndSettle();
    expect(find.textContaining('좌측: Original'), findsOneWidget);
    expect(find.textContaining('우측: birefnet (결과 없음)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(375, 568);
    await tester.pumpAndSettle();
    expect(find.textContaining('좌측: Original'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'each metric ranks only its own finite values and summary partitions',
      (WidgetTester tester) async {
    const memoryOnly = EngineResult(
      engineId: 'memory-only',
      name: 'Memory only',
      framework: 'test',
      description: 'test',
      latencyMs: null,
      peakMemoryMb: 10,
      outputPath: '/tmp/memory.png',
      maskPath: '/tmp/memory-mask.png',
      resolution: '32x32',
      codeSnippet: '',
      rankable: true,
      sessionReused: true,
    );
    const fullMetrics = EngineResult(
      engineId: 'full',
      name: 'Full metrics',
      framework: 'test',
      description: 'test',
      latencyMs: 20,
      peakMemoryMb: 30,
      outputPath: '/tmp/full.png',
      maskPath: '/tmp/full-mask.png',
      resolution: '32x32',
      codeSnippet: '',
      rankable: true,
    );
    const excluded = EngineResult(
      engineId: 'excluded',
      name: 'Excluded',
      framework: 'test',
      description: 'test',
      latencyMs: 5,
      peakMemoryMb: 5,
      outputPath: '/tmp/excluded.png',
      maskPath: '/tmp/excluded-mask.png',
      resolution: '32x32',
      codeSnippet: '',
      rankable: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 900,
            child: MetricsTableView(
              results: {
                'memory-only': memoryOnly,
                'full': fullMetrics,
                'excluded': excluded,
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Memory only'), findsNWidgets(2));
    expect(find.text('Full metrics'), findsNWidgets(3));
    expect(find.text('처리 시간 · cold/비상주'), findsOneWidget);
    expect(find.text('처리 시간 · warm'), findsOneWidget);
    expect(find.text('순위 허용 2'), findsOneWidget);
    expect(find.text('순위 제외 1'), findsOneWidget);
  });
}
