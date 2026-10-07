# Frequency Scanner

Aplicación Android (Flutter) que usa el micrófono del teléfono para analizar en
tiempo real las frecuencias presentes en el ambiente, muestra las componentes
dominantes y permite reproducir frecuencias de prueba con un generador de tonos
senoidales.

Es una herramienta técnica de análisis y generación de audio: no hace ninguna
afirmación médica, terapéutica ni de otro tipo.

## Funciones

- **Escaneo del micrófono** a 44,1 kHz, PCM 16 bits mono, sin control
  automático de ganancia ni supresión de ruido (fuente `VOICE_RECOGNITION`).
- **FFT** radix-2 de 8192 puntos (Δf ≈ 5,4 Hz) con ventana de Hann y 75 % de
  solapamiento (~21 análisis por segundo).
- **Frecuencias en Hz** con interpolación parabólica sub-bin (precisión < 1 Hz
  en tonos estables).
- **Intensidad en dBFS** (0 dB = escala completa del micrófono). El micrófono
  del teléfono no está calibrado: los niveles son relativos.
- **Detección de picos predominantes**: máximos locales que superan en 12 dB la
  mediana del espectro (ruido de fondo), sobre un espectro promediado para
  mayor estabilidad. Se descartan picos a menos del 2 % de otro más fuerte.
- **Frecuencias de prueba sugeridas** a partir del pico dominante: el propio
  pico, la nota afinada más cercana (A4 = 440 Hz), octava inferior y superior,
  banda de 1/3 de octava ISO 266 más cercana y segundo pico.
- **Generador de tonos** nativo (AudioTrack, 48 kHz) con fase continua y
  rampas de frecuencia/volumen para evitar chasquidos. Rango 20 Hz – 20 kHz.
- Controles para **iniciar / detener**, ajustar frecuencia (±1 / ±10 Hz) y
  **volumen**.
- **Espectro en tiempo real** con eje logarítmico 20 Hz – 20 kHz y marcador del
  pico dominante.

## Estructura

```
lib/
  main.dart                     Tema verde/blanco y arranque
  scanner_controller.dart       Estado: micrófono, análisis y generador
  audio/fft.dart                FFT radix-2 y ventana de Hann
  audio/spectrum_analyzer.dart  Buffer circular, espectro en dB, picos, PCM16
  audio/recommendations.dart    Notas musicales, bandas ISO 266, sugerencias
  audio/tone_generator.dart     Canal hacia el generador nativo
  models/frequency_peak.dart
  ui/home_screen.dart           Pantalla principal
  ui/widgets/spectrum_view.dart Gráfico del espectro (CustomPainter)
  ui/app_colors.dart            Paleta
android/app/src/main/kotlin/com/brekem/frequency_scanner/
  MainActivity.kt               MethodChannel del generador
  ToneGenerator.kt              Síntesis senoidal con AudioTrack
test/                           Pruebas de FFT, picos, PCM, sugerencias y UI
```

## Requisitos

- Flutter 3.47 (stable) o superior, JDK 17, Android SDK.
- Android 10 (API 29) o superior. Permiso `RECORD_AUDIO` declarado en el
  manifiesto y solicitado en tiempo de ejecución al pulsar **Escanear**.

## Compilar

```bash
flutter pub get
flutter test
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

Cada push a GitHub ejecuta el workflow **Build release APK**
(`.github/workflows/build-apk.yml`), que analiza, prueba y compila el APK; se
descarga desde la pestaña *Actions* → ejecución → *Artifacts*.

### Firma de release

Sin configuración adicional el APK release se firma con la clave de depuración
(instalable directamente). Para firmar con tu propia clave crea
`android/key.properties` (no se sube al repositorio):

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/ruta/a/upload-keystore.jks
```

## Notas de uso

- Empieza con el volumen bajo. Los altavoces de los teléfonos reproducen mal
  frecuencias por debajo de ~150 Hz y por encima de ~16 kHz.
- Si escaneas mientras suena un tono, el micrófono también lo captará.
- Al salir de la aplicación se detienen el micrófono y el generador.
