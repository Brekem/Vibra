import 'dart:math' as math;
import 'dart:typed_data';

import 'recommendations.dart';

/// Banda de frecuencia menos presente en el ambiente.
class MissingBand {
  const MissingBand({required this.frequency, required this.deficitDb});

  /// Frecuencia central nominal de la banda (ISO 266), en Hz.
  final double frequency;

  /// Cuántos dB está la banda por debajo de la media de las bandas analizadas.
  final double deficitDb;
}

/// Acumula la energía media por bandas de 1/3 de octava durante un escaneo.
///
/// En bandas de 1/3 de octava un ruido rosa (espectro "equilibrado", misma
/// energía por octava) es plano, así que la banda con menor nivel es la que
/// menos presencia tiene en el ambiente respecto a ese equilibrio.
class BandEnergyAccumulator {
  BandEnergyAccumulator({
    required double binHz,
    required int binCount,
    List<double> centers = iso266ThirdOctave,
  }) : centers = List.unmodifiable(centers),
       _lo = Int32List(centers.length),
       _hi = Int32List(centers.length),
       _sum = Float64List(centers.length) {
    final edge = math.pow(2, 1 / 6).toDouble();
    for (var i = 0; i < centers.length; i++) {
      final lo = (centers[i] / edge / binHz).ceil().clamp(1, binCount - 1);
      final hi = (centers[i] * edge / binHz).floor().clamp(1, binCount - 1);
      _lo[i] = lo;
      _hi[i] = math.max(lo, hi);
    }
  }

  final List<double> centers;
  final Int32List _lo;
  final Int32List _hi;
  final Float64List _sum;
  int _frames = 0;

  int get frames => _frames;

  void reset() {
    _sum.fillRange(0, _sum.length, 0);
    _frames = 0;
  }

  /// Añade un frame con la potencia (amplitud²) de cada bin.
  void addFrame(Float64List power) {
    for (var i = 0; i < centers.length; i++) {
      var p = 0.0;
      for (var k = _lo[i]; k <= _hi[i]; k++) {
        p += power[k];
      }
      _sum[i] += p;
    }
    _frames++;
  }

  /// Nivel medio de cada banda en dB.
  List<double> get bandDb => List.generate(centers.length, (i) {
    final p = _frames == 0 ? 0.0 : _sum[i] / _frames;
    return p <= 1e-24 ? -240.0 : 10 * math.log(p) / math.ln10;
  });

  /// Banda con menos energía entre [minHz] y [maxHz], o null si no hay datos
  /// suficientes (sin frames o ambiente en silencio total).
  MissingBand? leastPresent({double minHz = 200, double maxHz = 8000, double silenceDb = -110}) {
    if (_frames == 0) return null;
    final db = bandDb;
    var best = -1;
    var sum = 0.0;
    var n = 0;
    var loudest = double.negativeInfinity;
    for (var i = 0; i < centers.length; i++) {
      if (centers[i] < minHz || centers[i] > maxHz) continue;
      sum += db[i];
      n++;
      loudest = math.max(loudest, db[i]);
      if (best < 0 || db[i] < db[best]) best = i;
    }
    if (best < 0 || loudest < silenceDb) return null;
    return MissingBand(frequency: centers[best], deficitDb: sum / n - db[best]);
  }
}
