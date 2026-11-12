package com.itsash.seek

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import kotlin.math.PI
import kotlin.math.sin

/**
 * Sounds used by the finder.
 * - [beep]: a short click on the notification stream, so it stays on the phone speaker even when
 *   the lost earbuds are still connected as the media output.
 * - [playLoud]: a warbling tone on the media stream, which Android routes to a connected Bluetooth
 *   audio device (A2DP). User triggered; stops after [maxMillis] or on [stopLoud].
 */
class Tone {
    private val handler = Handler(Looper.getMainLooper())
    private var generator: ToneGenerator? = null
    private var track: AudioTrack? = null
    private val autoStop = Runnable { stopLoud() }

    fun beep(millis: Int) {
        try {
            val g = generator ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90).also { generator = it }
            g.startTone(ToneGenerator.TONE_PROP_BEEP, millis)
        } catch (_: RuntimeException) {
            generator = null
        }
    }

    fun playLoud() {
        stopLoud()
        val rate = 44100
        val frames = rate // one second: 4 x 0.25 s alternating 1.0 and 1.6 kHz
        val pcm = ShortArray(frames)
        var phase = 0.0
        for (i in 0 until frames) {
            val freq = if ((i / (rate / 4)) % 2 == 0) 1000.0 else 1600.0
            phase += 2 * PI * freq / rate
            pcm[i] = (sin(phase) * Short.MAX_VALUE * 0.9).toInt().toShort()
        }
        val t = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(frames * 2)
            .build()
        t.write(pcm, 0, frames)
        t.setLoopPoints(0, frames, -1)
        t.play()
        track = t
        handler.postDelayed(autoStop, MAX_MILLIS)
    }

    fun stopLoud() {
        handler.removeCallbacks(autoStop)
        track?.let {
            try {
                it.stop()
            } catch (_: IllegalStateException) {
            }
            it.release()
        }
        track = null
    }

    fun release() {
        stopLoud()
        generator?.release()
        generator = null
    }

    companion object {
        const val MAX_MILLIS = 20_000L
    }
}
