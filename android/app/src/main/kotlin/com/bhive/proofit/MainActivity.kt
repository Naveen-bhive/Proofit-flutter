package com.bhive.proofit

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.bhive.proofit/battery"

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val splashScreen = installSplashScreen()
            // Skip the default icon fly-to-corner animation on handoff to Flutter.
            splashScreen.setOnExitAnimationListener { view -> view.remove() }
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(requestIgnoreBatteryOptimizations())
                    }
                    "openBatteryOptimizationSettings" -> {
                        result.success(openBatteryOptimizationSettings())
                    }
                    "openOemAutostartSettings" -> {
                        result.success(openOemAutostartSettings())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (isIgnoringBatteryOptimizations()) return true
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            openBatteryOptimizationSettings()
        }
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    /**
     * Best-effort OEM autostart / protected-apps screens.
     * Manufacturers change these often — callers must still show manual steps.
     */
    private fun openOemAutostartSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val candidates = mutableListOf<Intent>()

        when {
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") -> {
                candidates += componentIntent("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
                candidates += componentIntent("com.miui.securitycenter", "com.miui.powercenter.PowerSettings")
            }
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                candidates += componentIntent("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")
                candidates += componentIntent("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")
                candidates += componentIntent("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")
            }
            manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
                candidates += componentIntent("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")
                candidates += componentIntent("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")
                candidates += componentIntent("com.coloros.oppoguardelf", "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity")
            }
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> {
                candidates += componentIntent("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")
                candidates += componentIntent("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")
                candidates += componentIntent("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager")
            }
            manufacturer.contains("oneplus") -> {
                candidates += componentIntent("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")
            }
            manufacturer.contains("samsung") -> {
                candidates += Intent().apply {
                    action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                    data = Uri.parse("package:$packageName")
                }
            }
        }

        // Always allow falling back to app details.
        candidates += Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }

        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
                // Try next candidate.
            }
        }
        return openBatteryOptimizationSettings()
    }

    private fun componentIntent(pkg: String, cls: String): Intent =
        Intent().apply {
            component = ComponentName(pkg, cls)
        }
}
