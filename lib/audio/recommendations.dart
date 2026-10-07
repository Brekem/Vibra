import 'dart:math' as math;

import '../models/frequency_peak.dart';

/// Frecuencia de prueba sugerida a partir del análisis.
class TestFrequency {
  const TestFrequency({required this.frequency, required this.label, required this.detail});

  final double frequency;
  final String label;
  final String detail;
}

const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// Frecuencias centrales nominales de bandas de 1/3 de octava (ISO 266).
const iso266ThirdOctave = <double>[
  20,
  25,
  31.5,
  40,
  50,
  63,
  80,
  100,
  125,
  160,
  200,
  250,
  315,
  400,
  500,
  630,
  800,
  1000,
  1250,
  1600,
  2000,
  2500,
  3150,
  4000,
  5000,
  6300,
  8000,
  10000,
  12500,
  16000,
  20000,
];

/// Nota musical más cercana en temperamento igual (A4 = 440 Hz).
class MusicalNote {
  const MusicalNote(this.name, this.frequency, this.cents);

  /// Nombre en notación anglosajona con octava, p. ej. "A4".
  final String name;

  /// Frecuencia exacta de la nota.
  final double frequency;

  /// Desviación de la frecuencia analizada respecto a la nota, en cents.
  final double cents;

  static MusicalNote? nearest(double frequency) {
    if (frequency <= 0 || !frequency.isFinite) return null;
    final midi = 69 + 12 * math.log(frequency / 440) / math.ln2;
    final n = midi.round();
    final noteFreq = 440 * math.pow(2, (n - 69) / 12).toDouble();
    final name = '${_noteNames[n % 12]}${n ~/ 12 - 1}';
    return MusicalNote(name, noteFreq, (midi - n) * 100);
  }
}

double nearestIsoBand(double frequency) {
  var best = iso266ThirdOctave.first;
  var bestDist = double.infinity;
  for (final f in iso266ThirdOctave) {
    final d = (math.log(frequency / f)).abs();
    if (d < bestDist) {
      bestDist = d;
      best = f;
    }
  }
  return best;
}

/// Etiqueta de la sugerencia principal: la frecuencia que falta en el ambiente.
const missingLabel = 'Frecuencia ausente';

/// Etiqueta de la frecuencia más presente (pico dominante) del ambiente.
const presentLabel = 'Frecuencia presente';

/// Genera las frecuencias sugeridas. La primera (y seleccionada por defecto)
/// es la banda menos presente en el ambiente ([missingFrequency]); después,
/// frecuencias relacionadas con el pico dominante: el propio pico, la nota
/// afinada más cercana, sus octavas, su banda de 1/3 de octava y el segundo pico.
List<TestFrequency> recommendTestFrequencies(
  List<FrequencyPeak> peaks, {
  double? missingFrequency,
}) {
  final result = <TestFrequency>[];

  void add(double f, String label, String detail) {
    if (f < 20 || f > 20000) return;
    final rounded = (f * 10).round() / 10;
    if (result.any((r) => (r.frequency - rounded).abs() < 0.5)) return;
    result.add(TestFrequency(frequency: rounded, label: label, detail: detail));
  }

  if (missingFrequency != null) {
    add(
      missingFrequency,
      missingLabel,
      'La banda con menos energía en tu ambiente (1/3 de octava, 200 Hz–8 kHz)',
    );
  }
  if (peaks.isEmpty) return result;
  final f0 = peaks.first.frequency;

  add(f0, presentLabel, 'El pico dominante: la componente más fuerte de tu ambiente');

  final note = MusicalNote.nearest(f0);
  if (note != null) {
    add(
      note.frequency,
      'Nota más cercana · ${note.name}',
      'Temperamento igual, A4 = 440 Hz (${_signed(note.cents)} cents)',
    );
  }

  add(f0 / 2, 'Octava inferior', 'Mitad de la frecuencia dominante');
  add(f0 * 2, 'Octava superior (2º armónico)', 'Doble de la frecuencia dominante');

  final band = nearestIsoBand(f0);
  add(band, 'Banda 1/3 de octava', 'Frecuencia central normalizada ISO 266');

  if (peaks.length > 1) {
    add(peaks[1].frequency, 'Segundo pico', 'Segunda componente más intensa');
  }
  return result;
}

String _signed(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)}';
