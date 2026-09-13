import 'package:equatable/equatable.dart';
import '../../core/models/engine_models.dart';

abstract class NukkiEvent extends Equatable {
  const NukkiEvent();

  @override
  List<Object?> get props => [];
}

class SelectSampleImageEvent extends NukkiEvent {
  final SampleImageInfo sample;
  const SelectSampleImageEvent(this.sample);

  @override
  List<Object?> get props => [sample];
}

class UploadCustomImageEvent extends NukkiEvent {
  final String filePath;
  const UploadCustomImageEvent(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class ChangeViewModeEvent extends NukkiEvent {
  final ComparisonViewMode mode;
  const ChangeViewModeEvent(this.mode);

  @override
  List<Object?> get props => [mode];
}

class ChangeBackgroundThemeEvent extends NukkiEvent {
  final BackgroundTheme theme;
  const ChangeBackgroundThemeEvent(this.theme);

  @override
  List<Object?> get props => [theme];
}

class SetCurtainSliderRatioEvent extends NukkiEvent {
  final double ratio;
  const SetCurtainSliderRatioEvent(this.ratio);

  @override
  List<Object?> get props => [ratio];
}

class SetCurtainEnginesEvent extends NukkiEvent {
  final String engineA;
  final String engineB;
  const SetCurtainEnginesEvent({required this.engineA, required this.engineB});

  @override
  List<Object?> get props => [engineA, engineB];
}

class RunBenchmarkEvent extends NukkiEvent {
  final String engineId;

  const RunBenchmarkEvent({this.engineId = 'all'});

  @override
  List<Object?> get props => [engineId];
}

class CancelBenchmarkEvent extends NukkiEvent {
  const CancelBenchmarkEvent();
}
