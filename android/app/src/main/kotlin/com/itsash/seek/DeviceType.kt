package com.itsash.seek

/**
 * Maps a Bluetooth class-of-device value to a short type name that the Dart side understands
 * (`earbuds`, `headphones`, `speaker`, `watch`, `band`, `audio`, `phone`, `computer`, `other`).
 * Pure: no Android types, so it is easy to test. `deviceClass` is `BluetoothClass.getDeviceClass()`,
 * or -1 when the device has no class (BLE only).
 */
object DeviceType {
    private const val MAJOR_MASK = 0x1F00

    fun classify(deviceClass: Int): String {
        if (deviceClass < 0) return "other"
        return when (deviceClass) {
            0x0404, 0x0408 -> "earbuds" // wearable headset, hands-free
            0x0418 -> "headphones"
            0x0414, 0x041C, 0x0428 -> "speaker" // loudspeaker, portable audio, hi-fi
            0x0704 -> "watch"
            else -> when (deviceClass and MAJOR_MASK) {
                0x0400 -> "audio"
                0x0200 -> "phone"
                0x0100 -> "computer"
                0x0700, 0x0900 -> "band" // wearable, health
                else -> "other"
            }
        }
    }
}
