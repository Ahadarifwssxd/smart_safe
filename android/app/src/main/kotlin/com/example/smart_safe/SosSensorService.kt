package com.example.smart_safe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import kotlin.math.sqrt

/**
 * Always-on shake / crash detection, done NATIVELY.
 *
 * Why native: Flutter's background isolate does NOT reliably receive
 * accelerometer events once the app is closed (the sensor plugin's event channel
 * is tied to the main engine). Detection therefore silently never fired. Running
 * the SensorEventListener inside this foreground service — with a partial wake
 * lock so the CPU keeps delivering events while the screen is off — is the only
 * dependable way to catch a shake or a crash when the app isn't running.
 *
 * On a detection we post a MAX-importance, full-screen-intent notification that
 * launches [MainActivity] with a `sos_kind` extra. The Flutter side then runs the
 * real SOS (call → WhatsApp → SMS), which a service cannot do on its own because
 * placing a call and opening WhatsApp both require a foreground Activity.
 */
class SosSensorService : Service(), SensorEventListener {

    companion object {
        const val CHANNEL_ID = "smartsafe_protection"
        const val ALERT_CHANNEL_ID = "sos_alerts"
        const val ONGOING_ID = 8820
        const val ALERT_ID = 8821

        /** Intent extra MainActivity reads to know what was detected. */
        const val EXTRA_SOS_KIND = "sos_kind"

        const val ACTION_START = "com.example.smart_safe.START_SOS_SENSOR"
        const val ACTION_STOP = "com.example.smart_safe.STOP_SOS_SENSOR"

        /** Sensitivity, kept in sync with the Flutter settings. */
        @Volatile var shakeEnabled: Boolean = true
        @Volatile var crashEnabled: Boolean = true
        /** m/s² magnitude that counts as a crash impact (Medium ≈ 3G). */
        @Volatile var crashThreshold: Float = 30f
    }

    private var sensorManager: SensorManager? = null
    private var wakeLock: PowerManager.WakeLock? = null

    // Shake: 3 spikes above SHAKE_THRESHOLD within SHAKE_WINDOW_MS.
    private val shakeThreshold = 18f
    private val shakeWindowMs = 2000L
    private val shakeGapMs = 400L
    private val shakeTimes = ArrayList<Long>()
    private var lastShakeAt = 0L

    // Cool-down so one event can't spam repeat alerts.
    private var lastAlertAt = 0L
    private val alertCooldownMs = 20_000L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        startAsForeground()
        acquireWakeLock()
        registerSensor()
        // START_STICKY: if the OS kills us for memory, come back.
        return START_STICKY
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "SmartSafe protection",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Keeps crash & shake detection running" }
        )
        nm.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "SOS Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Crash / shake SOS alerts"
                enableVibration(true)
            }
        )
    }

    private fun startAsForeground() {
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SmartSafe protection active")
            .setContentText("Crash & shake SOS running, even when the app is closed.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(open)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                ONGOING_ID, notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(ONGOING_ID, notif)
        }
    }

    /** Keeps the CPU alive so the accelerometer keeps delivering with screen off. */
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "SmartSafe::SosSensor"
        ).apply { acquire() }
    }

    private fun registerSensor() {
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensorManager = sm
        val accel = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        sm.registerListener(this, accel, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onDestroy() {
        try { sensorManager?.unregisterListener(this) } catch (_: Exception) {}
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
        super.onDestroy()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val magnitude = sqrt(x * x + y * y + z * z)
        val now = System.currentTimeMillis()

        // ── Shake: 3 deliberate spikes inside the window ──────────────────────
        if (magnitude > shakeThreshold) {
            if (now - lastShakeAt > shakeGapMs) {
                lastShakeAt = now
                shakeTimes.add(now)
                shakeTimes.removeAll { now - it > shakeWindowMs }
                if (shakeTimes.size >= 3) {
                    shakeTimes.clear()
                    if (shakeEnabled) raiseAlert("shake")
                }
            }
        }

        // ── Crash: a single high-G impact, but not while deliberately shaking ──
        if (crashEnabled && magnitude > crashThreshold && shakeTimes.size < 2) {
            raiseAlert("crash")
        }
    }

    /**
     * Posts a MAX-importance, full-screen-intent notification. On phones that
     * allow it this LAUNCHES the app by itself (even over the lock screen); where
     * the OEM blocks background launches (MIUI & friends) it still shows as a
     * heads-up banner the user can tap. Either way the app then runs the SOS.
     */
    private fun raiseAlert(kind: String) {
        val now = System.currentTimeMillis()
        if (now - lastAlertAt < alertCooldownMs) return
        lastAlertAt = now

        val launch = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_SOS_KIND, kind)
        }
        val fullScreen = PendingIntent.getActivity(
            this, kind.hashCode(), launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val isCrash = kind == "crash"
        val notif = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle(
                if (isCrash) "🚗 Crash detected — sending SOS"
                else "🆘 Shake SOS — alerting your contacts"
            )
            .setContentText("Tap to open SmartSafe and alert your emergency contacts.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setDefaults(Notification.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(fullScreen)
            .setFullScreenIntent(fullScreen, true)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(ALERT_ID, notif)
    }
}
