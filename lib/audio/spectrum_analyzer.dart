import 'dart:math' as math;
import 'dart:typed_data';

import '../models/frequency_peak.dart';
import 'fft.dart';

/// Analizador de espectro en tiempo real.
///
/// Recibe muestras de audio normalizadas en [-1, 1], las acumula en un buffer
/// circular y cada [hopSize] muestras nuevas calcula una FFT con ventana de
/// Hann sobre las últimas [fftSize] muestras (solapamiento del 75 % con los
/// valores por defecto).
class SpectrumAnalyzer {
  SpectrumAnalyzer({
    this.sampleRate = 44100,
    this.fftSize = 8192,
    this.hopSize = 2048,
    this.averaging = 0.25,
    this.displayReleaseDb = 1.5,
  }) : _fft = FFT(fftSize),
       _window = hannWindow(fftSize),
       _ring = Float64List(fftSize),
       _re = Float64List(fftSize),
       _im = Float64List(fftSize),
       _avgPower = Float64List(fftSize ~/ 2 + 1),
       displayDb = Float64List(fftSize ~/ 2 + 1)..fillRange(0, fftSize ~/ 2 + 1, minDb),
       averageDb = Float64List(fftSize ~/ 2 + 1)..fillRange(0, fftSize ~/ 2 + 1, minDb) {
    var sum = 0.0;
    for (final w in _window) {
      sum += w;
    }
    _windowSum = sum;
  }

  /// Nivel mínimo representado (suelo del gráfico).
  static const double minDb = -120;

  final int sampleRate;
  final int fftSize;
  final int hopSize;

  /// Coeficiente del promedio exponencial de potencia usado para detectar picos
  /// (0 < averaging <= 1; más bajo = más estable, más lento).
  final double averaging;

  /// Caída en dB por frame del espectro mostrado (efecto "caída suave").
  final double displayReleaseDb;

  final FFT _fft;
  final Float64List _window;
  late final double _windowSum;
  final Float64List _ring;
  final Float64List _re;
  final Float64List _im;
  final Float64List _avgPower;

  int _writePos = 0;
  int _filled = 0;
  int _sinceLastFrame = 0;
  bool _hasAverage = false;

  /// Espectro instantáneo para el visualizador (ataque rápido, caída suave).
  final Float64List displayDb;

  /// Espectro promediado (más estable) usado para detectar picos.
  final Float64List averageDb;

  /// Nivel RMS del último bloque analizado, en dBFS.
  double levelDb = minDb;

  /// Picos predominantes del último frame, ordenados de mayor a menor nivel.
  List<FrequencyPeak> peaks = const [];

  /// Resolución en frecuencia de cada bin de la FFT.
  double get binHz => sampleRate / fftSize;

  int get binCount => fftSize ~/ 2 + 1;

  void reset() {
    _ring.fillRange(0, _ring.length, 0);
    _avgPower.fillRange(0, _avgPower.length, 0);
    displayDb.fillRange(0, displayDb.length, minDb);
    averageDb.fillRange(0, averageDb.length, minDb);
    _writePos = 0;
    _filled = 0;
    _sinceLastFrame = 0;
    _hasAverage = false;
    levelDb = minDb;
    peaks = const [];
  }

  /// Añade muestras y devuelve cuántos frames de FFT se han calculado.
  int addSamples(List<double> samples) {
    var frames = 0;
    for (final s in samples) {
      _ring[_writePos] = s;
      _writePos = (_writePos + 1) % fftSize;
      if (_filled < fftSize) _filled++;
      _sinceLastFrame++;
      if (_filled == fftSize && _sinceLastFrame >= hopSize) {
        _sinceLastFrame = 0;
        _processFrame();
        frames++;
      }
    }
    return frames;
  }

  void _processFrame() {
    // Copia ordenada del buffer circular, eliminando la componente continua.
    var mean = 0.0;
    for (var i = 0; i < fftSize; i++) {
      mean += _ring[i];
    }
    mean /= fftSize;

    var sumSq = 0.0;
    for (var i = 0; i < fftSize; i++) {
      final s = _ring[(_writePos + i) % fftSize] - mean;
      sumSq += s * s;
      _re[i] = s * _window[i];
      _im[i] = 0;
    }
    levelDb = _toDb(math.sqrt(sumSq / fftSize));

    _fft.transform(_re, _im);

    final a = _hasAverage ? averaging : 1.0;
    _hasAverage = true;
    final last = binCount - 1;
    for (var k = 0; k <= last; k++) {
      final mag = math.sqrt(_re[k] * _re[k] + _im[k] * _im[k]);
      // Amplitud de pico de una senoidal equivalente (corrigiendo la ventana).
      final amp = (k == 0 || k == last ? 1.0 : 2.0) * mag / _windowSum;
      final db = _toDb(amp);

      final prev = displayDb[k];
      displayDb[k] = db >= prev ? db : math.max(db, prev - displayReleaseDb);

      _avgPower[k] = _avgPower[k] * (1 - a) + amp * amp * a;
      averageDb[k] = _toDb(math.sqrt(_avgPower[k]));
    }

    peaks = findPeaks(averageDb, binHz);
  }

  static double _toDb(double amplitude) {
    if (amplitude <= 1e-12) return minDb;
    return math.max(minDb, 20 * math.log(amplitude) / math.ln10);
  }

  /// Busca los máximos locales más relevantes de un espectro en dB.
  ///
  /// Un bin se considera pico si es máximo local en ±2 bins, supera
  /// [minPeakDb] y sobresale al menos [prominenceDb] respecto a la mediana del
  /// espectro (estimación del ruido de fondo). La frecuencia se refina con
  /// interpolación parabólica y se descartan picos demasiado próximos a otro
  /// más fuerte (lóbulos de la misma componente).
  static List<FrequencyPeak> findPeaks(
    Float64List db,
    double binHz, {
    int maxPeaks = 8,
    double minPeakDb = -90,
    double prominenceDb = 12,
    double minFrequency = 20,
    double maxFrequency = 20000,
  }) {
    final kMin = math.max(2, (minFrequency / binHz).ceil());
    final kMax = math.min(db.length - 3, (maxFrequency / binHz).floor());
    if (kMax <= kMin) return const [];

    final band = Float64List.fromList(db.sublist(kMin, kMax + 1))..sort();
    final median = band[band.length ~/ 2];
    final threshold = math.max(minPeakDb, median + prominenceDb);

    final candidates = <FrequencyPeak>[];
    for (var k = kMin; k <= kMax; k++) {
      final v = db[k];
      if (v < threshold) continue;
      if (!(v > db[k - 1] && v >= db[k + 1] && v > db[k - 2] && v >= db[k + 2])) {
        continue;
      }
      final alpha = db[k - 1];
      final gamma = db[k + 1];
      final denom = alpha - 2 * v + gamma;
      final p = denom == 0 ? 0.0 : (0.5 * (alpha - gamma) / denom).clamp(-0.5, 0.5);
      candidates.add(FrequencyPeak(frequency: (k + p) * binHz, db: v - 0.25 * (alpha - gamma) * p));
    }

    candidates.sort((x, y) => y.db.compareTo(x.db));
    final selected = <FrequencyPeak>[];
    for (final c in candidates) {
      final tooClose = selected.any(
        (s) => (s.frequency - c.frequency).abs() < math.max(3 * binHz, 0.02 * s.frequency),
      );
      if (tooClose) continue;
      selected.add(c);
      if (selected.length >= maxPeaks) break;
    }
    return selected;
  }
}

/// Convierte un flujo de bytes PCM 16 bits little-endian en muestras [-1, 1],
/// conservando el byte sobrante si un bloque llega con longitud impar.
class Pcm16Decoder {
  int? _pending;

  List<double> decode(Uint8List bytes) {
    var offset = 0;
    final total = bytes.length + (_pending != null ? 1 : 0);
    final out = List<double>.filled(total ~/ 2, 0);
    var o = 0;
    if (_pending != null && bytes.isNotEmpty) {
      out[o++] = _toSample(_pending!, bytes[0]);
      offset = 1;
      _pending = null;
    }
    for (; offset + 1 < bytes.length; offset += 2) {
      out[o++] = _toSample(bytes[offset], bytes[offset + 1]);
    }
    if (offset < bytes.length) _pending = bytes[offset];
    return out;
  }

  void reset() => _pending = null;

  static double _toSample(int lo, int hi) {
    var v = (hi << 8) | lo;
    if (v >= 0x8000) v -= 0x10000;
    return v / 32768.0;
  }
}
