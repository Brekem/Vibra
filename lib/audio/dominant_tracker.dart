import 'dart:math' as math;

/// Acumula la frecuencia dominante de cada análisis durante un periodo y
/// devuelve la más estable: agrupa por semitono, elige el grupo que más veces
/// fue dominante (a igualdad, el de mayor nivel medio) y devuelve la mediana
/// de ese grupo.
class DominantTracker {
  final Map<int, List<double>> _freqs = {};
  final Map<int, double> _dbSum = {};
  int _count = 0;

  int get sampleCount => _count;

  void reset() {
    _freqs.clear();
    _dbSum.clear();
    _count = 0;
  }

  void add(double frequency, double db) {
    if (frequency <= 0 || !frequency.isFinite) return;
    final bucket = (12 * math.log(frequency / 440) / math.ln2).round();
    _freqs.putIfAbsent(bucket, () => []).add(frequency);
    _dbSum[bucket] = (_dbSum[bucket] ?? 0) + db;
    _count++;
  }

  /// Frecuencia dominante más estable del periodo, o null si no hubo datos.
  double? get stableFrequency {
    int? best;
    for (final b in _freqs.keys) {
      if (best == null) {
        best = b;
        continue;
      }
      final n = _freqs[b]!.length;
      final bestN = _freqs[best]!.length;
      if (n > bestN || (n == bestN && _dbSum[b]! / n > _dbSum[best]! / bestN)) {
        best = b;
      }
    }
    if (best == null) return null;
    final sorted = [..._freqs[best]!]..sort();
    return sorted[sorted.length ~/ 2];
  }
}
