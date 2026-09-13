import 'package:flutter/material.dart';
import '../../core/models/engine_models.dart';

class BackgroundPatternWidget extends StatelessWidget {
  final BackgroundTheme theme;
  final Widget child;

  const BackgroundPatternWidget({
    super.key,
    required this.theme,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    switch (theme) {
      case BackgroundTheme.pureBlack:
        return ColoredBox(color: Colors.black, child: child);
      case BackgroundTheme.pureWhite:
        return ColoredBox(color: Colors.white, child: child);
      case BackgroundTheme.chromaGreen:
        return ColoredBox(color: const Color(0xFF00FF00), child: child);
      case BackgroundTheme.checkerboard:
        return RepaintBoundary(
          child: CustomPaint(
            isComplex: true,
            willChange: false,
            painter: const OptimizedCheckerboardPainter(),
            child: child,
          ),
        );
    }
  }
}

class OptimizedCheckerboardPainter extends CustomPainter {
  final double cellSize;
  final Color color1;
  final Color color2;

  const OptimizedCheckerboardPainter({
    this.cellSize = 12.0,
    this.color1 = const Color(0xFFE2E2E2),
    this.color2 = const Color(0xFFFFFFFF),
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw entire canvas with color2 first (Single GPU operation)
    canvas.drawPaint(Paint()..color = color2);

    // 2. Draw only alternating cells with color1 (Halves draw calls)
    final paint1 = Paint()..color = color1;
    final int cols = (size.width / cellSize).ceil();
    final int rows = (size.height / cellSize).ceil();

    final path = Path();
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if ((r + c) % 2 == 0) {
          path.addRect(
              Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize));
        }
      }
    }
    canvas.drawPath(path, paint1);
  }

  @override
  bool shouldRepaint(covariant OptimizedCheckerboardPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize ||
      oldDelegate.color1 != color1 ||
      oldDelegate.color2 != color2;
}

class BackgroundToolbarToggle extends StatelessWidget {
  final BackgroundTheme currentTheme;
  final ValueChanged<BackgroundTheme> onThemeChanged;
  final bool compact;

  const BackgroundToolbarToggle({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!compact)
            const Padding(
              padding: EdgeInsets.only(right: 2),
              child: Text(
                '배경',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          _buildButton(
            label: '🏁 격자',
            tooltip: '투명도 확인',
            theme: BackgroundTheme.checkerboard,
          ),
          _buildButton(
            label: '⬛ 블랙',
            tooltip: '흰색 테두리/헤일로 확인',
            theme: BackgroundTheme.pureBlack,
          ),
          _buildButton(
            label: '⬜ 화이트',
            tooltip: '경계 손실/깎임 확인',
            theme: BackgroundTheme.pureWhite,
          ),
          _buildButton(
            label: '🟩 크로마',
            tooltip: '반투명 투과율 확인',
            theme: BackgroundTheme.chromaGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required String tooltip,
    required BackgroundTheme theme,
  }) {
    final isSelected = currentTheme == theme;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          selected: isSelected,
          onSelected: (_) => onThemeChanged(theme),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
