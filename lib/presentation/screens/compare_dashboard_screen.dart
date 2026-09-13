import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/nukki_bloc.dart';
import '../bloc/nukki_event.dart';
import '../bloc/nukki_state.dart';
import '../widgets/benchmark_action_button.dart';
import '../widgets/comparison_workspace.dart';
import '../widgets/metrics_table_view.dart';
import '../widgets/photo_source_panel.dart';

class CompareDashboardScreen extends StatelessWidget {
  const CompareDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<NukkiBloc, NukkiState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage &&
          current.errorMessage != null,
      listener: (context, state) {
        final message = state.errorMessage;
        if (message == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 1,
          title: const Text(
            '🖼️ CompareNukki',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          actions: const [
            _BenchmarkAppBarAction(),
            SizedBox(width: 12),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(3),
            child: _BenchmarkAppBarProgress(),
          ),
        ),
        body: const _DashboardBody(),
      ),
    );
  }
}

class _BenchmarkAppBarAction extends StatelessWidget {
  const _BenchmarkAppBarAction();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NukkiBloc, NukkiState>(
      buildWhen: (previous, current) =>
          previous.isLoading != current.isLoading ||
          previous.isLocalWorkerSupported != current.isLocalWorkerSupported,
      builder: (context, state) {
        final compact = MediaQuery.sizeOf(context).width < 600;
        return BenchmarkActionButton(
          isRunning: state.isLoading,
          workerSupported: state.isLocalWorkerSupported,
          compactLabel: compact,
          onRun: () => context.read<NukkiBloc>().add(const RunBenchmarkEvent()),
          onCancel: () =>
              context.read<NukkiBloc>().add(const CancelBenchmarkEvent()),
        );
      },
    );
  }
}

class _BenchmarkAppBarProgress extends StatelessWidget {
  const _BenchmarkAppBarProgress();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NukkiBloc, NukkiState>(
      buildWhen: (previous, current) =>
          previous.isLoading != current.isLoading ||
          previous.progress != current.progress,
      builder: (context, state) {
        if (!state.isLoading) return const SizedBox(height: 3);
        final progress = state.progress.clamp(0.0, 1.0);
        return LinearProgressIndicator(
          value: progress > 0 ? progress : null,
          minHeight: 3,
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NukkiBloc, NukkiState>(
      buildWhen: (previous, current) =>
          previous.currentImage != current.currentImage ||
          previous.viewMode != current.viewMode ||
          previous.bgTheme != current.bgTheme ||
          previous.results != current.results ||
          previous.curtainRatio != current.curtainRatio ||
          previous.curtainEngineA != current.curtainEngineA ||
          previous.curtainEngineB != current.curtainEngineB ||
          previous.progress != current.progress ||
          previous.activeEngineId != current.activeEngineId ||
          previous.benchmarkPhase != current.benchmarkPhase,
      builder: (context, state) {
        final bloc = context.read<NukkiBloc>();
        final activeEngineName = state.activeEngineId == null
            ? null
            : state.results[state.activeEngineId]?.name ?? state.activeEngineId;

        final photoPanel = PhotoSourcePanel(
          currentImage: state.currentImage,
          samples: state.availableSamples,
          isRunning: state.isLoading,
          progress: state.progress,
          benchmarkPhase: state.benchmarkPhase,
          activeEngineName: activeEngineName,
          workerSupported: state.isLocalWorkerSupported,
          onSampleSelected: (sample) =>
              bloc.add(SelectSampleImageEvent(sample)),
          onImageUploaded: (path) => bloc.add(UploadCustomImageEvent(path)),
          onRun: () => bloc.add(const RunBenchmarkEvent()),
          onCancel: () => bloc.add(const CancelBenchmarkEvent()),
        );
        final comparisonPanel = ComparisonWorkspace(
          currentImage: state.currentImage,
          results: state.results,
          viewMode: state.viewMode,
          bgTheme: state.bgTheme,
          curtainRatio: state.curtainRatio,
          curtainEngineA: state.curtainEngineA,
          curtainEngineB: state.curtainEngineB,
          isRunning: state.isLoading,
          progress: state.progress,
          activeEngineId: state.activeEngineId,
          onViewModeChanged: (mode) => bloc.add(ChangeViewModeEvent(mode)),
          onBackgroundThemeChanged: (theme) =>
              bloc.add(ChangeBackgroundThemeEvent(theme)),
          onCurtainRatioChanged: (ratio) =>
              bloc.add(SetCurtainSliderRatioEvent(ratio)),
          onCurtainEnginesChanged: (engineA, engineB) => bloc.add(
            SetCurtainEnginesEvent(engineA: engineA, engineB: engineB),
          ),
        );
        final metricsPanel = MetricsTableView(
          results: state.results,
          compact: true,
          padding: const EdgeInsets.all(14),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1180) {
              return _WideWorkspace(
                photoPanel: photoPanel,
                comparisonPanel: comparisonPanel,
                metricsPanel: metricsPanel,
              );
            }
            return _CompactWorkspace(
              photoPanel: photoPanel,
              comparisonPanel: comparisonPanel,
              metricsPanel: metricsPanel,
            );
          },
        );
      },
    );
  }
}

class _WideWorkspace extends StatelessWidget {
  const _WideWorkspace({
    required this.photoPanel,
    required this.comparisonPanel,
    required this.metricsPanel,
  });

  final Widget photoPanel;
  final Widget comparisonPanel;
  final Widget metricsPanel;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 276, child: photoPanel),
        VerticalDivider(width: 1, thickness: 1, color: borderColor),
        Expanded(child: comparisonPanel),
        VerticalDivider(width: 1, thickness: 1, color: borderColor),
        SizedBox(width: 354, child: metricsPanel),
      ],
    );
  }
}

class _CompactWorkspace extends StatefulWidget {
  const _CompactWorkspace({
    required this.photoPanel,
    required this.comparisonPanel,
    required this.metricsPanel,
  });

  final Widget photoPanel;
  final Widget comparisonPanel;
  final Widget metricsPanel;

  @override
  State<_CompactWorkspace> createState() => _CompactWorkspaceState();
}

class _CompactWorkspaceState extends State<_CompactWorkspace> {
  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              widget.photoPanel,
              widget.comparisonPanel,
              widget.metricsPanel,
            ],
          ),
        ),
        NavigationBar(
          height: 64,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.add_photo_alternate_outlined),
              selectedIcon: Icon(Icons.add_photo_alternate),
              label: '사진 추가',
            ),
            NavigationDestination(
              icon: Icon(Icons.compare_outlined),
              selectedIcon: Icon(Icons.compare),
              label: 'Compare',
            ),
            NavigationDestination(
              icon: Icon(Icons.query_stats_outlined),
              selectedIcon: Icon(Icons.query_stats),
              label: '지표 비교',
            ),
          ],
        ),
      ],
    );
  }
}
