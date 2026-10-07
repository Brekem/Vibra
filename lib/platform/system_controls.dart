import 'package:flutter/services.dart';

/// Funciones del sistema Android: pantalla encendida y servicio en primer
/// plano para mantener el audio activo en segundo plano (ver MainActivity.kt).
class SystemControls {
  static const _channel = MethodChannel('com.brekem.frequency_scanner/system');

  /// Registra la acción del botón "Detener" de la notificación.
  void setStopHandler(void Function() onStop) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopRequested') onStop();
    });
  }

  Future<void> keepScreenOn(bool on) => _invoke('keepScreenOn', {'on': on});

  Future<void> startBackgroundService(String text) => _invoke('startService', {'text': text});

  Future<void> updateBackgroundService(String text) => _invoke('updateService', {'text': text});

  Future<void> stopBackgroundService() => _invoke('stopService');

  Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Plataforma sin implementación nativa (p. ej. pruebas).
    } on PlatformException {
      // Un fallo aquí no debe interrumpir el escaneo ni el tono.
    }
  }
}
