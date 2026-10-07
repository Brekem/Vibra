import 'package:flutter/services.dart';

/// Generador de tonos senoidales implementado de forma nativa con AudioTrack
/// (ver MainActivity.kt). Mantiene la fase continua al cambiar frecuencia o
/// volumen, por lo que los ajustes en vivo no producen chasquidos.
class ToneGenerator {
  static const _channel = MethodChannel('com.brekem.frequency_scanner/tone');

  Future<void> start({required double frequency, required double amplitude}) =>
      _channel.invokeMethod<void>('start', {'frequency': frequency, 'amplitude': amplitude});

  Future<void> update({required double frequency, required double amplitude}) =>
      _channel.invokeMethod<void>('update', {'frequency': frequency, 'amplitude': amplitude});

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
