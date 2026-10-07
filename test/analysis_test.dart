import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frequency_scanner/audio/fft.dart';
import 'package:frequency_scanner/audio/recommendations.dart';
import 'package:frequency_scanner/audio/spectrum_analyzer.dart';
import 'package:frequency_scanner/models/frequency_peak.dart';

List<double> sine(List<(double, double)> components, int n, {int rate = 44100}) =>
    List<double>.generate(n, (i) {
      var v = 0.0;
      for (final (f, a) in components) {
        v += a * math.sin(2 * math.pi * f * i / rate);
      }
      return v;
    });

void main() {
  test('FFT de una senoidal concentra la energía en su bin', () {
    const n = 1024;
    final fft = FFT(n);
    final re = Float64List.fromList(List.generate(n, (i) => math.sin(2 * math.pi * 64 * i / n)));
    final im = Float64List(n);
    fft.transform(re, im);
    final mags = List.generate(n ~/ 2, (k) => math.sqrt(re[k] * re[k] + im[k] * im[k]));
    expect(mags.indexOf(mags.reduce(math.max)), 64);
    expect(mags[64], closeTo(n / 2, 1e-6));
  });

  test('El analizador detecta frecuencia y nivel de un tono puro', () {
    final analyzer = SpectrumAnalyzer();
    analyzer.addSamples(sine([(1000, 0.5)], 44100));
    final peak = analyzer.peaks.first;
    expect(peak.frequency, closeTo(1000, 1.0));
    // 0.5 de amplitud ≈ -6 dBFS
    expect(peak.db, closeTo(-6.02, 1.0));
  });

  test('El analizador ordena varios picos por intensidad', () {
    final analyzer = SpectrumAnalyzer();
    final noise = math.Random(1);
    final samples = sine([
      (440, 0.3),
      (2500, 0.1),
      (120, 0.05),
    ], 44100).map((s) => s + (noise.nextDouble() - 0.5) * 0.001).toList();
    analyzer.addSamples(samples);
    final freqs = analyzer.peaks.take(3).map((p) => p.frequency).toList();
    expect(freqs[0], closeTo(440, 1.5));
    expect(freqs[1], closeTo(2500, 1.5));
    expect(freqs[2], closeTo(120, 1.5));
  });

  test('El silencio no produce picos', () {
    final analyzer = SpectrumAnalyzer();
    analyzer.addSamples(List.filled(20000, 0.0));
    expect(analyzer.peaks, isEmpty);
  });

  test('Decodificador PCM16 conserva bytes entre bloques', () {
    final decoder = Pcm16Decoder();
    // 0x7FFF, 0x8000 (-32768), 0x0001 repartidos en bloques impares.
    final a = decoder.decode(Uint8List.fromList([0xFF, 0x7F, 0x00]));
    final b = decoder.decode(Uint8List.fromList([0x80, 0x01, 0x00]));
    expect(a, [closeTo(32767 / 32768, 1e-9)]);
    expect(b, [-1.0, closeTo(1 / 32768, 1e-9)]);
  });

  test('Nota musical más cercana', () {
    final a4 = MusicalNote.nearest(442)!;
    expect(a4.name, 'A4');
    expect(a4.frequency, closeTo(440, 1e-9));
    expect(a4.cents, closeTo(7.85, 0.1));
    expect(MusicalNote.nearest(261.6)!.name, 'C4');
  });

  test('Recomendaciones derivadas del pico dominante', () {
    final recs = recommendTestFrequencies(const [
      FrequencyPeak(frequency: 1003.2, db: -20),
      FrequencyPeak(frequency: 3000, db: -30),
    ]);
    final freqs = recs.map((r) => r.frequency).toList();
    expect(freqs.first, 1003.2);
    expect(freqs, containsAll([501.6, 2006.4, 1000.0, 3000.0]));
    expect(nearestIsoBand(1003.2), 1000);
    expect(recommendTestFrequencies(const []), isEmpty);
  });
}
