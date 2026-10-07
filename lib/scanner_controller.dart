import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'audio/dominant_tracker.dart';
import 'audio/recommendations.dart';
import 'audio/spectrum_analyzer.dart';
import 'audio/tone_generator.dart';
import 'models/frequency_peak.dart';
import 'platform/system_controls.dart';

/// Fase actual del modo continuo.
enum CyclePhase { scanning, playing }

/// Qué frecuencia se reproduce con "Reproducir" y en el modo continuo.
enum FrequencySource {
  /// La banda menos presente en el ambiente.
  missing,

  /// El pico dominante (la frecuencia más presente).
  present,

  /// Una frecuencia escrita por el usuario.
  manual,
}

/// Estado de la aplicación: captura de micrófono, análisis, generador de tonos
/// y modo continuo (ciclos de escaneo + reproducción que se repiten sin fin).
class ScannerController extends ChangeNotifier {
  ScannerController({
    AudioRecorder? recorder,
    ToneGenerator? toneGenerator,
    SystemControls? systemControls,
    this.cycleScanDuration = const Duration(minutes: 1),
    this.cyclePlayDuration = const Duration(minutes: 10),
  }) : _recorderOverride = recorder,
       _tone = toneGenerator ?? ToneGenerator(),
       _system = systemControls ?? SystemControls() {
    _system.setStopHandler(stopAll);
  }

  /// Duración de la fase de escaneo en el modo continuo.
  final Duration cycleScanDuration;

  /// Duración de la fase de reproducción en el modo continuo.
  final Duration cyclePlayDuration;

  static const int sampleRate = 44100;
  static const double minToneHz = 20;
  static const double maxToneHz = 20000;

  final AudioRecorder? _recorderOverride;
  AudioRecorder? _recorder;
  final ToneGenerator _tone;
  final SystemControls _system;
  final DominantTracker _tracker = DominantTracker();
  final SpectrumAnalyzer analyzer = SpectrumAnalyzer(sampleRate: sampleRate);
  final Pcm16Decoder _decoder = Pcm16Decoder();
  StreamSubscription<Uint8List>? _subscription;

  bool _scanning = false;
  bool _busy = false;
  bool _playing = false;
  double _volume = 0.3;
  double _toneFrequency = 440;
  String _selectedLabel = missingLabel;
  bool _manualSelected = false;
  double _manualFrequency = 432;
  List<FrequencyPeak> _peaks = const [];
  List<TestFrequency> _recommendations = const [];
  String? _message;

  bool _cycleActive = false;
  CyclePhase _phase = CyclePhase.scanning;
  int _cycleCount = 0;
  DateTime? _phaseEnd;
  Timer? _phaseTimer;
  Timer? _ticker;

  bool _screenKeptOn = false;
  bool _serviceOn = false;
  bool _serviceHasMic = false;
  String? _serviceText;

  bool get isScanning => _scanning;
  bool get isBusy => _busy;
  bool get isPlaying => _playing;
  double get volume => _volume;
  double get toneFrequency => _toneFrequency;
  List<FrequencyPeak> get peaks => _peaks;
  FrequencyPeak? get dominant => _peaks.isEmpty ? null : _peaks.first;
  double get levelDb => analyzer.levelDb;
  List<TestFrequency> get recommendations => _recommendations;
  double get manualFrequency => _manualFrequency;

  /// Índice de la sugerencia seleccionada en la lista (-1 si se usa la manual).
  int get selectedRecommendation =>
      _manualSelected ? -1 : _recommendations.indexWhere((r) => r.label == _selectedLabel);

  /// Fuente de frecuencia elegida, o null si se seleccionó otra sugerencia de la lista.
  FrequencySource? get source {
    if (_manualSelected) return FrequencySource.manual;
    if (_selectedLabel == missingLabel) return FrequencySource.missing;
    if (_selectedLabel == presentLabel) return FrequencySource.present;
    return null;
  }

  bool get isCycleActive => _cycleActive;
  CyclePhase get cyclePhase => _phase;
  int get cycleCount => _cycleCount;

  /// Tiempo restante de la fase actual del modo continuo.
  Duration get phaseRemaining {
    final end = _phaseEnd;
    if (end == null) return Duration.zero;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Frecuencia que se reproducirá: la manual o la sugerencia seleccionada.
  TestFrequency? get suggested {
    if (_manualSelected) {
      return TestFrequency(
        frequency: _manualFrequency,
        label: 'Frecuencia manual',
        detail: 'Escrita por ti',
      );
    }
    for (final r in _recommendations) {
      if (r.label == _selectedLabel) return r;
    }
    return null;
  }

  /// Mensaje puntual para mostrar al usuario (se consume al leerlo).
  String? takeMessage() {
    final m = _message;
    _message = null;
    return m;
  }

  Future<void> toggleScan() => _scanning ? stopScan() : startScan();

  Future<void> startScan() async {
    if (_scanning || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final recorder = _recorder ??= _recorderOverride ?? AudioRecorder();
      if (!await recorder.hasPermission()) {
        _message =
            'Se necesita permiso de micrófono para escanear. '
            'Puedes activarlo en Ajustes > Aplicaciones > Frequency Scanner.';
        return;
      }
      analyzer.reset();
      _decoder.reset();
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
          // Sin pausas por cambios de foco de audio (p. ej. al sonar un tono).
          audioInterruption: AudioInterruptionMode.none,
          androidConfig: AndroidRecordConfig(
            // Fuente sin control automático de ganancia ni supresión de ruido.
            audioSource: AndroidAudioSource.voiceRecognition,
            manageBluetooth: false,
          ),
        ),
      );
      _subscription = stream.listen(
        _onAudio,
        onError: (Object e) {
          _message = 'Error de captura de audio: $e';
          stopScan();
        },
      );
      _scanning = true;
    } catch (e) {
      _message = 'No se pudo iniciar el micrófono: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    _scanning = false;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder?.stop();
    } catch (_) {
      // El grabador ya estaba detenido.
    }
    notifyListeners();
  }

  void _onAudio(Uint8List bytes) {
    final frames = analyzer.addSamples(_decoder.decode(bytes));
    if (frames == 0) return;
    _peaks = analyzer.peaks;
    if (_peaks.isNotEmpty) _tracker.add(_peaks.first.frequency, _peaks.first.db);
    _recommendations = recommendTestFrequencies(
      _peaks,
      missingFrequency: analyzer.bands.leastPresent()?.frequency,
    );
    notifyListeners();
  }

  void selectRecommendation(int index) {
    if (index < 0 || index >= _recommendations.length) return;
    _selectedLabel = _recommendations[index].label;
    _manualSelected = false;
    notifyListeners();
  }

  /// Elige qué frecuencia reproducir: ausente, presente o manual.
  void setSource(FrequencySource source) {
    switch (source) {
      case FrequencySource.missing:
        _selectedLabel = missingLabel;
        _manualSelected = false;
      case FrequencySource.present:
        _selectedLabel = presentLabel;
        _manualSelected = false;
      case FrequencySource.manual:
        _manualSelected = true;
    }
    notifyListeners();
  }

  /// Fija la frecuencia escrita por el usuario y la selecciona. Si ya suena un
  /// tono (también durante la reproducción del modo continuo) cambia al momento.
  Future<void> setManualFrequency(double frequency) async {
    _manualFrequency = frequency.clamp(minToneHz, maxToneHz).toDouble();
    _manualSelected = true;
    if (_playing) {
      await playTone(_manualFrequency);
    } else {
      _toneFrequency = _manualFrequency;
      notifyListeners();
    }
  }

  /// Reproduce la frecuencia sugerida seleccionada (o la detiene si ya suena).
  Future<void> togglePlaySuggested() async {
    if (_playing) return stopTone();
    final s = suggested;
    if (s == null) {
      _message = source == FrequencySource.present
          ? 'Primero escanea el ambiente para detectar la frecuencia presente.'
          : 'Primero escanea el ambiente para obtener la frecuencia ausente.';
      notifyListeners();
      return;
    }
    await playTone(s.frequency);
  }

  Future<void> playTone(double frequency) async {
    _toneFrequency = frequency.clamp(minToneHz, maxToneHz);
    try {
      if (_playing) {
        await _tone.update(frequency: _toneFrequency, amplitude: _amplitude);
      } else {
        await _tone.start(frequency: _toneFrequency, amplitude: _amplitude);
        _playing = true;
      }
    } catch (e) {
      _playing = false;
      _message = 'No se pudo reproducir el tono: $e';
    }
    notifyListeners();
  }

  Future<void> toggleTone() => _playing ? stopTone() : playTone(_toneFrequency);

  Future<void> stopTone() async {
    if (!_playing) return;
    _playing = false;
    notifyListeners();
    try {
      await _tone.stop();
    } catch (_) {
      // Nada que detener.
    }
  }

  Future<void> adjustFrequency(double delta) => setToneFrequency(_toneFrequency + delta);

  Future<void> setToneFrequency(double frequency) async {
    _toneFrequency = frequency.clamp(minToneHz, maxToneHz);
    notifyListeners();
    if (_playing) {
      await _tone.update(frequency: _toneFrequency, amplitude: _amplitude);
    }
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    notifyListeners();
    if (_playing) {
      await _tone.update(frequency: _toneFrequency, amplitude: _amplitude);
    }
  }

  /// Curva cuadrática: el control de volumen resulta más natural al oído.
  double get _amplitude => _volume * _volume * 0.9;

  // ---------------------------------------------------------------------------
  // Modo continuo: escaneo -> reproducción de la frecuencia detectada -> ...
  // ---------------------------------------------------------------------------

  Future<void> toggleCycle() => _cycleActive ? stopAll() : startCycle();

  Future<void> startCycle() async {
    if (_cycleActive || _busy) return;
    await stopTone();
    await stopScan();
    _cycleActive = true;
    _cycleCount = 1;
    await _beginScanPhase();
    if (!_scanning) {
      // Sin permiso de micrófono o error al iniciar: se cancela el modo.
      await stopAll();
      return;
    }
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
  }

  Future<void> _beginScanPhase() async {
    _phase = CyclePhase.scanning;
    _tracker.reset();
    await stopTone();
    await startScan();
    _schedulePhase(cycleScanDuration, _endScanPhase);
  }

  Future<void> _endScanPhase() async {
    if (!_cycleActive) return;
    final stable = _tracker.stableFrequency;
    final db = dominant?.db ?? 0;
    // Energía por bandas acumulada durante todo el escaneo de esta fase.
    final missing = analyzer.bands.leastPresent()?.frequency;
    await stopScan();
    // Sugerencias calculadas con todo el minuto de escaneo, manteniendo la
    // fuente elegida (ausente, presente, manual u otra sugerencia de la lista).
    _recommendations = recommendTestFrequencies([
      if (stable != null) FrequencyPeak(frequency: stable, db: db),
    ], missingFrequency: missing);
    if (suggested == null) {
      _message = 'No se detectó la frecuencia elegida; se repite el escaneo.';
      await _beginScanPhase();
      return;
    }

    _phase = CyclePhase.playing;
    await playTone(suggested!.frequency);
    _schedulePhase(cyclePlayDuration, _endPlayPhase);
  }

  Future<void> _endPlayPhase() async {
    if (!_cycleActive) return;
    _cycleCount++;
    await _beginScanPhase();
  }

  void _schedulePhase(Duration duration, Future<void> Function() next) {
    _phaseTimer?.cancel();
    _phaseEnd = DateTime.now().add(duration);
    _phaseTimer = Timer(duration, next);
    notifyListeners();
  }

  void _cancelCycle() {
    _cycleActive = false;
    _phaseTimer?.cancel();
    _phaseTimer = null;
    _ticker?.cancel();
    _ticker = null;
    _phaseEnd = null;
  }

  /// Detiene el modo continuo, el escaneo y el tono.
  Future<void> stopAll() async {
    _cancelCycle();
    await stopScan();
    await stopTone();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Pantalla encendida y servicio en segundo plano.
  // ---------------------------------------------------------------------------

  @override
  void notifyListeners() {
    _syncPlatform();
    super.notifyListeners();
  }

  void _syncPlatform() {
    final keepOn = _scanning;
    if (keepOn != _screenKeptOn) {
      _screenKeptOn = keepOn;
      _system.keepScreenOn(keepOn);
    }

    final active = _scanning || _playing || _cycleActive;
    if (!active) {
      if (_serviceOn) {
        _serviceOn = false;
        _serviceHasMic = false;
        _serviceText = null;
        _system.stopBackgroundService();
      }
      return;
    }
    final text = _statusText;
    // El servicio se (re)inicia con tipo "micrófono" cuando hay escaneo, para
    // que la captura siga funcionando con la app en segundo plano.
    if (!_serviceOn || (_scanning && !_serviceHasMic)) {
      _serviceOn = true;
      _serviceHasMic = _scanning;
      _serviceText = text;
      _system.startBackgroundService(text);
    } else if (text != _serviceText) {
      _serviceText = text;
      _system.updateBackgroundService(text);
    }
  }

  String get _statusText {
    final tone = '${_toneFrequency.toStringAsFixed(1)} Hz';
    if (_cycleActive) {
      return _phase == CyclePhase.scanning
          ? 'Modo continuo · ciclo $_cycleCount · escaneando'
          : 'Modo continuo · ciclo $_cycleCount · reproduciendo $tone';
    }
    if (_scanning && _playing) return 'Escaneando · reproduciendo $tone';
    if (_scanning) return 'Escaneando el micrófono';
    return 'Reproduciendo $tone';
  }

  @override
  void dispose() {
    _cancelCycle();
    _subscription?.cancel();
    _recorder?.dispose();
    _tone.stop().catchError((_) {});
    if (_screenKeptOn) _system.keepScreenOn(false);
    if (_serviceOn) _system.stopBackgroundService();
    super.dispose();
  }
}
