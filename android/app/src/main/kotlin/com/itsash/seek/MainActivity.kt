package com.itsash.seek

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Channels (see CLAUDE.md for the contract):
 * - MethodChannel `com.itsash.seek/control`
 * - EventChannel `com.itsash.seek/scan`: the scan runs only while Dart listens.
 */
class MainActivity : FlutterActivity() {
    private lateinit var scanner: Scanner
    private val tone = Tone()
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        scanner = Scanner(
            this,
            emit = { sink?.success(it) },
            fail = { code, message -> sink?.error(code, message, null) },
        )

        MethodChannel(messenger, "com.itsash.seek/control").setMethodCallHandler(::onMethod)

        EventChannel(messenger, "com.itsash.seek/scan").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
                val classic = (arguments as? Map<*, *>)?.get("classic") as? Boolean ?: true
                if (!hasPermissions()) {
                    events.error("PERMISSION", "Bluetooth permission is needed.", null)
                    return
                }
                scanner.start(classic)
            }

            override fun onCancel(arguments: Any?) {
                scanner.stop()
                sink = null
            }
        })
    }

    private fun onMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> {
                val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
                result.success(
                    mapOf(
                        "supported" to (adapter != null),
                        "enabled" to (adapter?.isEnabled == true),
                        "permitted" to hasPermissions(),
                    )
                )
            }
            "requestPermissions" -> {
                if (hasPermissions()) {
                    result.success(true)
                } else {
                    pendingPermission?.success(false)
                    pendingPermission = result
                    requestPermissions(requiredPermissions(), REQUEST_BT)
                }
            }
            "openBluetoothSettings" -> {
                startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            "bonded" -> result.success(bondedDevices())
            "beep" -> {
                tone.beep(call.argument<Int>("ms") ?: 80)
                result.success(null)
            }
            "vibrate" -> {
                vibrate((call.argument<Int>("ms") ?: 60).toLong())
                result.success(null)
            }
            "playTone" -> {
                tone.playLoud()
                result.success(null)
            }
            "stopTone" -> {
                tone.stopLoud()
                result.success(null)
            }
            "keepAwake" -> {
                val on = call.argument<Boolean>("on") ?: false
                if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= 31) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasPermissions(): Boolean =
        requiredPermissions().all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    @SuppressLint("MissingPermission")
    private fun bondedDevices(): List<Map<String, Any?>> {
        if (!hasPermissions()) return emptyList()
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: return emptyList()
        return try {
            adapter.bondedDevices.orEmpty().map { d ->
                mapOf(
                    "address" to d.address,
                    "name" to d.name,
                    "type" to DeviceType.classify(d.bluetoothClass?.deviceClass ?: -1),
                    "bonded" to true,
                )
            }
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(millis: Long) {
        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        vibrator.vibrate(VibrationEffect.createOneShot(millis, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_BT) {
            pendingPermission?.success(hasPermissions())
            pendingPermission = null
        }
    }

    override fun onStop() {
        // Never keep scanning or playing in the background.
        scanner.stop()
        tone.stopLoud()
        super.onStop()
    }

    override fun onDestroy() {
        scanner.stop()
        tone.release()
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_BT = 4201
    }
}
