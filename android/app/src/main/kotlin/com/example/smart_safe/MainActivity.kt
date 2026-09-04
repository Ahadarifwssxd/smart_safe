package com.example.smart_safe

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "smartsafe/oem"
    private var channel: MethodChannel? = null

    /** Set when the native detector launched us; delivered to Dart once ready. */
    private var pendingSosKind: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSosIntent(intent)
    }

    /** Reads the "sos_kind" extra the native SosSensorService attaches. */
    private fun handleSosIntent(intent: Intent?) {
        val kind = intent?.getStringExtra(SosSensorService.EXTRA_SOS_KIND) ?: return
        intent.removeExtra(SosSensorService.EXTRA_SOS_KIND)
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("onSosDetected", kind)
        } else {
            pendingSosKind = kind
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch
        ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Starts / stops the NATIVE shake+crash detector. Flutter's
                    // background isolate can't reliably read the accelerometer once
                    // the app is closed, so detection lives in SosSensorService.
                    "startSensorService" -> {
                        SosSensorService.shakeEnabled =
                            call.argument<Boolean>("shake") ?: true
                        SosSensorService.crashEnabled =
                            call.argument<Boolean>("crash") ?: true
                        SosSensorService.crashThreshold =
                            (call.argument<Double>("crashThreshold") ?: 30.0).toFloat()
                        val i = Intent(this, SosSensorService::class.java).apply {
                            action = SosSensorService.ACTION_START
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(i)
                            } else {
                                startService(i)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "stopSensorService" -> {
                        try {
                            stopService(Intent(this, SosSensorService::class.java))
                        } catch (_: Exception) {}
                        result.success(true)
                    }
                    // Live-update the detector's settings without restarting it.
                    "updateSensorSettings" -> {
                        SosSensorService.shakeEnabled =
                            call.argument<Boolean>("shake") ?: true
                        SosSensorService.crashEnabled =
                            call.argument<Boolean>("crash") ?: true
                        SosSensorService.crashThreshold =
                            (call.argument<Double>("crashThreshold") ?: 30.0).toFloat()
                        result.success(true)
                    }
                    // If the native detector launched us before Dart was listening,
                    // hand the pending detection over now.
                    "consumePendingSos" -> {
                        val k = pendingSosKind
                        pendingSosKind = null
                        result.success(k)
                    }
                    // Opens the OEM "Autostart / background start" settings page so
                    // the user can allow SmartSafe to run when closed. Aggressive
                    // OEMs (Xiaomi/MIUI, Oppo/Realme, Vivo, Huawei) each bury this
                    // in their own security app — we try the known screens in turn
                    // and fall back gracefully if none match. Returns true if a
                    // settings screen was opened.
                    "openAutoStart" -> result.success(openAutoStartSettings())
                    // Opens the app's per-app permission editor (MIUI) so the user
                    // can grant "Display pop-up windows while running in background"
                    // + "Show on lock screen" — required for the crash/shake alert
                    // to POP THE APP OPEN by itself. Falls back to the standard app
                    // details page on non-MIUI devices.
                    "openBgPopupPermission" ->
                        result.success(openAppPermissionSettings())
                    else -> result.notImplemented()
                }
            }

        // COLD LAUNCH from the native detector: Dart isn't listening yet, so stash
        // the detection — Dart pulls it with "consumePendingSos" once it's ready.
        intent?.getStringExtra(SosSensorService.EXTRA_SOS_KIND)?.let { kind ->
            pendingSosKind = kind
            intent.removeExtra(SosSensorService.EXTRA_SOS_KIND)
        }
    }

    private fun openAutoStartSettings(): Boolean {
        val components = listOf(
            // Xiaomi / MIUI / Redmi / Poco
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            // Oppo / Realme (ColorOS)
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.startupapp.StartupAppListActivity"
            ),
            ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
            // Vivo (Funtouch / iQOO)
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
            ComponentName(
                "com.iqoo.secure",
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
            ),
            // Huawei / Honor
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"
            )
        )
        for (cn in components) {
            try {
                val intent = Intent().apply {
                    component = cn
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Not this OEM — try the next known screen.
            }
        }
        return false
    }

    /// Opens the per-app permission editor. On MIUI this is the screen that holds
    /// "Display pop-up windows while running in background" + "Show on lock
    /// screen" — the switches that let the crash/shake alert pop the app open by
    /// itself. Falls back to the standard system App-info page elsewhere.
    private fun openAppPermissionSettings(): Boolean {
        // MIUI-specific permission editor first.
        try {
            val intent = Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity"
                )
                putExtra("extra_pkgname", packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return true
        } catch (_: Exception) {
        }
        // Fallback: the standard Android App-info page (Permissions live there).
        try {
            val intent = Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:$packageName")
            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            startActivity(intent)
            return true
        } catch (_: Exception) {
        }
        return false
    }
}
