package com.brekem.frequency_scanner

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/**
 * Generador de tonos senoidales en tiempo real con AudioTrack (modo stream).
 *
 * La fase se acumula de forma continua y la frecuencia y la amplitud se
 * suavizan muestra a muestra, de modo que los cambios en vivo y el inicio o
 * parada del tono no producen chasquidos.
 */
class ToneGenerator {
    @Volatile private var targetFrequency = 440.0
    @Volatile private var targetAmplitude = 0.0
    @Volatile private var stopRequested = false

    private var thread: Thread? = null
    private val lock = Any()

    fun start(frequency: Double, amplitude: Double) {
        synchronized(lock) {
            update(frequency, amplitude)
            if (thread?.isAlive == true && !stopRequested) return
            thread?.join(STOP_TIMEOUT_MS)
            stopRequested = false
            thread = Thread({ render() }, "ToneGenerator").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
        }
    }

    fun update(frequency: Double, amplitude: Double) {
        targetFrequency = frequency.coerceIn(MIN_FREQUENCY, MAX_FREQUENCY)
        targetAmplitude = amplitude.coerceIn(0.0, MAX_AMPLITUDE)
    }

    fun stop() {
        synchronized(lock) {
            stopRequested = true
            thread?.join(STOP_TIMEOUT_MS)
            thread = null
        }
    }

    private fun render() {
        val minBuffer = AudioTrack.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(minBuffer, BLOCK_SIZE * 2 * 2))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        val block = ShortArray(BLOCK_SIZE)
        var phase = 0.0
        var frequency = targetFrequency
        var amplitude = 0.0
        // Coeficientes de suavizado (~10 ms para amplitud, ~20 ms para frecuencia).
        val ampSmoothing = 1.0 / (SAMPLE_RATE * 0.010)
        val freqSmoothing = 1.0 / (SAMPLE_RATE * 0.020)

        try {
            track.play()
            while (true) {
                val stopping = stopRequested
                val ampTarget = if (stopping) 0.0 else targetAmplitude
                val freqTarget = targetFrequency
                for (i in 0 until BLOCK_SIZE) {
                    amplitude += (ampTarget - amplitude) * ampSmoothing
                    frequency += (freqTarget - frequency) * freqSmoothing
                    phase += TWO_PI * frequency / SAMPLE_RATE
                    if (phase >= TWO_PI) phase -= TWO_PI
                    block[i] = (sin(phase) * amplitude * Short.MAX_VALUE).toInt().toShort()
                }
                track.write(block, 0, BLOCK_SIZE)
                if (stopping && abs(amplitude) < 1e-4) break
            }
        } finally {
            try {
                track.stop()
            } catch (e: IllegalStateException) {
                // La pista ya estaba detenida.
            }
            track.release()
        }
    }

    companion object {
        private const val SAMPLE_RATE = 48000
        private const val BLOCK_SIZE = 1024
        private const val TWO_PI = 2 * PI
        private const val MIN_FREQUENCY = 20.0
        private const val MAX_FREQUENCY = 20000.0
        private const val MAX_AMPLITUDE = 0.95
        private const val STOP_TIMEOUT_MS = 500L
    }
}
