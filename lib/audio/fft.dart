import 'dart:math' as math;
import 'dart:typed_data';

/// Transformada rápida de Fourier radix-2 (Cooley–Tukey) in-place.
///
/// Las tablas de senos/cosenos y de inversión de bits se precalculan una vez
/// por tamaño, por lo que [transform] no reserva memoria en cada llamada.
class FFT {
  FFT(this.size)
    : assert(size > 1 && (size & (size - 1)) == 0, 'El tamaño de la FFT debe ser potencia de 2'),
      _cos = Float64List(size ~/ 2),
      _sin = Float64List(size ~/ 2),
      _rev = Int32List(size) {
    for (var i = 0; i < size ~/ 2; i++) {
      final angle = -2 * math.pi * i / size;
      _cos[i] = math.cos(angle);
      _sin[i] = math.sin(angle);
    }
    final bits = (math.log(size) / math.ln2).round();
    for (var i = 0; i < size; i++) {
      var r = 0;
      var x = i;
      for (var b = 0; b < bits; b++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
      }
      _rev[i] = r;
    }
  }

  final int size;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _rev;

  /// Calcula la FFT de ([re], [im]) sobrescribiendo ambos buffers.
  void transform(Float64List re, Float64List im) {
    final n = size;
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final step = n ~/ len;
      for (var start = 0; start < n; start += len) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step];
          final wi = _sin[k * step];
          final a = start + k;
          final b = a + half;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}

/// Ventana de Hann de longitud [n].
Float64List hannWindow(int n) {
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
  }
  return w;
}
