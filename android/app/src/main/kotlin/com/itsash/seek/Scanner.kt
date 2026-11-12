package com.itsash.seek

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * One scan session: a low-latency BLE scan plus (optional) classic discovery, restarted each
 * time it ends. Every sighting goes to [emit] as a map:
 * `{address, name?, rssi, kind: "le" | "classic", type, bonded}`. Callbacks run on the main thread.
 * Always call [stop] when the screen leaves.
 */
@SuppressLint("MissingPermission") // The caller checks permissions before start().
class Scanner(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
    private val fail: (String, String) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var scanning = false
    private var classic = false
    private var registered = false

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private val leCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (!scanning) return
            val device = result.device
            val name = result.scanRecord?.deviceName ?: safeName(device)
            emit(sighting(device, name, result.rssi, "le"))
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            for (r in results) onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, r)
        }

        override fun onScanFailed(errorCode: Int) {
            fail("SCAN_FAILED", "Bluetooth LE scan failed (code $errorCode).")
        }
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    } ?: return
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE).toInt()
                    if (rssi == Short.MIN_VALUE.toInt()) return
                    val name = intent.getStringExtra(BluetoothDevice.EXTRA_NAME) ?: safeName(device)
                    emit(sighting(device, name, rssi, "classic"))
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    if (scanning && classic) handler.postDelayed({ startDiscovery() }, 400)
                }
            }
        }
    }

    fun start(withClassic: Boolean) {
        stop()
        val a = adapter
        if (a == null || !a.isEnabled) {
            fail("BLUETOOTH_OFF", "Bluetooth is off.")
            return
        }
        scanning = true
        classic = withClassic
        try {
            val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
            a.bluetoothLeScanner?.startScan(null, settings, leCallback)
        } catch (e: SecurityException) {
            fail("PERMISSION", "Bluetooth permission was denied.")
            scanning = false
            return
        }
        if (classic) {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            context.registerReceiver(receiver, filter)
            registered = true
            startDiscovery()
        }
    }

    fun stop() {
        scanning = false
        handler.removeCallbacksAndMessages(null)
        val a = adapter
        try {
            a?.bluetoothLeScanner?.stopScan(leCallback)
            if (a?.isDiscovering == true) a.cancelDiscovery()
        } catch (_: SecurityException) {
        } catch (_: IllegalStateException) {
        }
        if (registered) {
            try {
                context.unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            }
            registered = false
        }
    }

    private fun startDiscovery() {
        if (!scanning || !classic) return
        try {
            val a = adapter ?: return
            if (!a.isDiscovering) a.startDiscovery()
        } catch (_: SecurityException) {
        }
    }

    private fun safeName(device: BluetoothDevice): String? =
        try {
            device.name
        } catch (_: SecurityException) {
            null
        }

    companion object {
        fun sighting(device: BluetoothDevice, name: String?, rssi: Int, kind: String): Map<String, Any?> {
            val cls = try {
                device.bluetoothClass?.deviceClass ?: -1
            } catch (_: SecurityException) {
                -1
            }
            val bonded = try {
                device.bondState == BluetoothDevice.BOND_BONDED
            } catch (_: SecurityException) {
                false
            }
            return mapOf(
                "address" to device.address,
                "name" to name,
                "rssi" to rssi,
                "kind" to kind,
                "type" to DeviceType.classify(cls),
                "bonded" to bonded,
            )
        }
    }
}
