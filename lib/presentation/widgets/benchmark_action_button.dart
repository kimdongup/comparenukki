import 'package:flutter/material.dart';

class BenchmarkActionButton extends StatelessWidget {
  const BenchmarkActionButton({
    super.key,
    required this.isRunning,
    required this.workerSupported,
    required this.onRun,
    required this.onCancel,
    this.compactLabel = false,
  });

  final bool isRunning;
  final bool workerSupported;
  final VoidCallback onRun;
  final VoidCallback onCancel;
  final bool compactLabel;

  @override
  Widget build(BuildContext context) {
    if (isRunning) {
      return OutlinedButton.icon(
        onPressed: onCancel,
        icon: const Icon(Icons.stop_circle_outlined, size: 17),
        label: compactLabel
            ? const SizedBox.shrink()
            : const Text('실행 취소', style: TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return FilledButton.icon(
      onPressed: workerSupported ? onRun : null,
      icon: const Icon(Icons.play_arrow, size: 17),
      label: compactLabel
          ? const SizedBox.shrink()
          : const Text('벤치마크 실행', style: TextStyle(fontSize: 11)),
      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}
