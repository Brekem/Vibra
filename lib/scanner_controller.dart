import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'audio/recommendations.dart';
import 'audio/spectrum_analyzer.dart';
import 'audio/tone_generator.dart';
import 'models/frequency_peak.dart';

/// Estado de la aplicación: captura de micrófono, análisis y generador de tonos.
class ScannerController extends ChangeNotifier {
  ScannerController({AudioRecorder? recorder, ToneGenerator? toneGenerator})
    : _recorderOverride = recorder,
      _tone = toneGenerator ?? ToneGenerator();

  static const int sampleRate = 44100;
  static const double minToneHz = 20;
  static const double maxToneHz = 20000;

  final AudioRecorder? _recorderOverride;
  AudioRecorder? _recorder;
  final ToneGenerator _tone;
  final SpectrumAnalyzer analyzer = SpectrumAnalyzer(sampleRate: sampleRate);
  final Pcm16Decoder _decoder = Pcm16Decoder();
  StreamSubscription<Uint8List>? _subscription;

  bool _scanning = false;
  bool _busy = false;
  bool _playing = false;
  double _volume = 0.3;
  double _toneFrequency = 440;
  int _selected = 0;
  List<FrequencyPeak> _peaks = const [];
  List<TestFrequency> _recommendations = const [];
  String? _message;

  bool get isScanning => _scanning;
  bool get isBusy => _busy;
  bool get isPlaying => _playing;
  double get volume => _volume;
  double get toneFrequency => _toneFrequency;
  List<FrequencyPeak> get peaks => _peaks;
  FrequencyPeak? get dominant => _peaks.isEmpty ? null : _peaks.first;
  double get levelDb => analyzer.levelDb;
  List<TestFrequency> get recommendations => _recommendations;
  int get selectedRecommendation => _selected;

  TestFrequency? get suggested => _recommendations.isEmpty
      ? null
      : _recommendations[_selected.clamp(0, _recommendations.length - 1)];

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
    final previous = suggested?.label;
    _recommendations = recommendTestFrequencies(_peaks);
    // Mantiene seleccionada la misma categoría de sugerencia si sigue existiendo.
    final idx = _recommendations.indexWhere((r) => r.label == previous);
    _selected = idx >= 0 ? idx : 0;
    notifyListeners();
  }

  void selectRecommendation(int index) {
    if (index < 0 || index >= _recommendations.length) return;
    _selected = index;
    notifyListeners();
  }

  /// Reproduce la frecuencia sugerida seleccionada (o la detiene si ya suena).
  Future<void> togglePlaySuggested() async {
    if (_playing) return stopTone();
    final s = suggested;
    if (s == null) {
      _message = 'Primero escanea el ambiente para obtener una sugerencia.';
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

  Future<void> stopAll() async {
    await stopScan();
    await stopTone();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _recorder?.dispose();
    _tone.stop().catchError((_) {});
    super.dispose();
  }
}
