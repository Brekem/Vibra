/// Una frecuencia predominante detectada en el espectro.
class FrequencyPeak {
  const FrequencyPeak({required this.frequency, required this.db});

  /// Frecuencia estimada en Hz (con interpolación sub-bin).
  final double frequency;

  /// Nivel en dBFS (0 dB = escala completa del micrófono).
  final double db;
}
