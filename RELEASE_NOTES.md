## Frequency Scanner

Analizador de espectro de audio en tiempo real y generador de tonos senoidales para Android 10 o superior.

### Instalación
1. Descarga el archivo `.apk` de la sección **Assets**.
2. Ábrelo en el teléfono y permite la instalación desde esta fuente si Android lo pide.
3. Al pulsar **Escanear**, concede el permiso de micrófono (y el de notificaciones en Android 13+).

### Funciones
- Escaneo del micrófono con FFT de 8192 puntos: frecuencias en Hz e intensidad en dBFS.
- Frecuencia dominante, lista de frecuencias detectadas y espectro en tiempo real.
- Frecuencia a reproducir: **Ausente** (la banda menos presente en el ambiente), **Presente** (el pico dominante) o **Manual** (escribe cualquier valor de 20 a 20000 Hz).
- Generador de tonos senoidales con ajuste de frecuencia y volumen.
- **Modo continuo** infinito: 1 min de escaneo y 10 min de reproducción, repetidos hasta detenerlo.
- La pantalla no se apaga mientras escanea.
- El audio continúa en segundo plano y se detiene desde la notificación.

APK firmado con la clave de depuración (instalación directa, no apto para Google Play).
