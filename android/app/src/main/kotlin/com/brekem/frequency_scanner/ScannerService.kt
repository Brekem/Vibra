package com.brekem.frequency_scanner

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Servicio en primer plano que mantiene vivo el proceso mientras se escanea o
 * suena un tono, para que el audio continúe con la app en segundo plano o con
 * la pantalla apagada. Muestra una notificación con un botón "Detener".
 */
class ScannerService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FrequencyScanner:audio").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopListener?.invoke()
            return START_NOT_STICKY
        }
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: DEFAULT_TEXT
        startForeground(NOTIFICATION_ID, buildNotification(this, text), serviceType())
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    private fun serviceType(): Int {
        var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        ) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        return type
    }

    companion object {
        private const val CHANNEL_ID = "frequency_scanner_audio"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_STOP = "com.brekem.frequency_scanner.STOP"
        private const val EXTRA_TEXT = "text"
        private const val DEFAULT_TEXT = "Audio activo"

        /** Se invoca cuando el usuario pulsa "Detener" en la notificación. */
        var stopListener: (() -> Unit)? = null

        fun start(context: Context, text: String) {
            ensureChannel(context)
            val intent = Intent(context, ScannerService::class.java).putExtra(EXTRA_TEXT, text)
            context.startForegroundService(intent)
        }

        fun update(context: Context, text: String) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification(context, text))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ScannerService::class.java))
        }

        private fun ensureChannel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID, "Audio en segundo plano", NotificationManager.IMPORTANCE_LOW
                ).apply { description = "Escaneo y reproducción de tonos activos" }
                manager.createNotificationChannel(channel)
            }
        }

        private fun buildNotification(context: Context, text: String): Notification {
            val openIntent = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val stopIntent = PendingIntent.getService(
                context, 1,
                Intent(context, ScannerService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            return Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_launcher_foreground)
                .setContentTitle("Frequency Scanner")
                .setContentText(text)
                .setContentIntent(openIntent)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .addAction(
                    Notification.Action.Builder(null, "Detener", stopIntent).build()
                )
                .build()
        }
    }
}
