import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'presentation/bloc/nukki_bloc.dart';
import 'presentation/screens/compare_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Optimize ImageCache to prevent memory bloat during multi-image comparisons
  PaintingBinding.instance.imageCache.maximumSize =
      64; // Max 64 images in cache
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      128 * 1024 * 1024; // Max 128MB cache

  runApp(const CompareNukkiApp());
}

class CompareNukkiApp extends StatelessWidget {
  const CompareNukkiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => NukkiBloc.owned(),
      child: MaterialApp(
        title: 'CompareNukki - 8-Engine Background Removal Benchmark',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5),
            brightness: Brightness.light,
          ),
        ),
        home: const CompareDashboardScreen(),
      ),
    );
  }
}
