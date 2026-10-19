package com.bandpassrecords.dpm

import android.content.Context
import android.content.pm.PackageManager
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiManager
import android.media.midi.MidiOutputPort
import android.media.midi.MidiReceiver
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Native half of MIDI input on Android (a USB keyboard through an OTG
/// adapter, say), through android.media.midi, answering the channels
/// ChannelMidiInput (lib/services/midi/input/channel_midi_input.dart) talks
/// on — the same contract as MidiInputBridge on macOS and iOS: `devices`,
/// `open` (answering the ids that wouldn't open), `close`, and `{id, bytes}`
/// events.
///
/// An input is a device's *output* port: what it sends out is what the app
/// takes in. Its id is "<device id>:<port number>".
class MidiInputBridge(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val opened = mutableListOf<Pair<MidiDevice, MidiOutputPort>>()

    /// Bumped by every open and close, so a device that finishes opening
    /// after it was no longer wanted is closed instead of kept.
    private var generation = 0

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.bandpassrecords.dpm/midi_input")
            .setMethodCallHandler(this)
        EventChannel(messenger, "com.bandpassrecords.dpm/midi_input/events")
            .setStreamHandler(this)
    }

    /// Null on a device without MIDI support.
    private val manager: MidiManager?
        get() {
            if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_MIDI)) {
                return null
            }
            return context.getSystemService(Context.MIDI_SERVICE) as? MidiManager
        }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "devices" -> result.success(devices())
            "open" -> open(call.argument<List<String>>("ids") ?: emptyList(), result)
            "close" -> {
                close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION") // getDevicesForTransport needs Android 13.
    private fun deviceInfos(): List<MidiDeviceInfo> {
        val manager = manager ?: return emptyList()
        return manager.devices.toList()
    }

    private fun devices(): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        for (info in deviceInfos()) {
            val outputs = info.ports.filter { it.type == MidiDeviceInfo.PortInfo.TYPE_OUTPUT }
            val name = info.properties.getString(MidiDeviceInfo.PROPERTY_NAME) ?: "MIDI"
            for (port in outputs) {
                val portName = port.name
                list.add(
                    mapOf(
                        "id" to "${info.id}:${port.portNumber}",
                        // A device with several outputs names each one.
                        "name" to if (outputs.size > 1 && !portName.isNullOrBlank()) "$name $portName" else name,
                    )
                )
            }
        }
        return list
    }

    private fun open(ids: List<String>, result: MethodChannel.Result) {
        close()
        val manager = manager
        if (manager == null || ids.isEmpty()) {
            result.success(ids)
            return
        }
        val wanted = generation
        val infos = deviceInfos()
        val failed = mutableListOf<String>()
        var pending = ids.size
        fun done(id: String, ok: Boolean) {
            if (!ok) failed.add(id)
            pending -= 1
            if (pending == 0) result.success(failed)
        }
        for (id in ids) {
            val parts = id.split(":")
            val deviceId = parts.getOrNull(0)?.toIntOrNull()
            val portNumber = parts.getOrNull(1)?.toIntOrNull()
            val info = infos.firstOrNull { it.id == deviceId }
            if (info == null || portNumber == null) {
                done(id, false)
                continue
            }
            manager.openDevice(info, { device ->
                if (device == null) {
                    done(id, false)
                    return@openDevice
                }
                if (wanted != generation) {
                    device.close()
                    done(id, false)
                    return@openDevice
                }
                val port = device.openOutputPort(portNumber)
                if (port == null) {
                    // Another app has it.
                    device.close()
                    done(id, false)
                    return@openDevice
                }
                port.connect(object : MidiReceiver() {
                    override fun onSend(msg: ByteArray, offset: Int, count: Int, timestamp: Long) {
                        val bytes = msg.copyOfRange(offset, offset + count)
                        main.post { sink?.success(mapOf("id" to id, "bytes" to bytes)) }
                    }
                })
                opened.add(device to port)
                done(id, true)
            }, main)
        }
    }

    private fun close() {
        generation += 1
        for ((device, port) in opened) {
            try {
                port.close()
                device.close()
            } catch (e: Exception) {
                // Unplugged meanwhile: nothing left to let go of.
            }
        }
        opened.clear()
    }
}
