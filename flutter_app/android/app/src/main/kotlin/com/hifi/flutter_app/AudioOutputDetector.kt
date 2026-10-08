package com.hifi.flutter_app

import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import org.json.JSONObject

class AudioOutputDetector(
    private val context: Context,
    private val onOutputChanged: (JSONObject) -> Unit
) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var bluetoothA2dp: BluetoothA2dp? = null

    private val bluetoothProfileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile == BluetoothProfile.A2DP) {
                bluetoothA2dp = proxy as BluetoothA2dp
                dispatchCurrentOutput()
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.A2DP) {
                bluetoothA2dp = null
                dispatchCurrentOutput()
            }
        }
    }

    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
            dispatchCurrentOutput()
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
            dispatchCurrentOutput()
        }
    }

    fun start() {
        audioManager.registerAudioDeviceCallback(audioDeviceCallback, null)
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        bluetoothAdapter?.getProfileProxy(context, bluetoothProfileListener, BluetoothProfile.A2DP)
        dispatchCurrentOutput()
    }

    fun stop() {
        audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        bluetoothA2dp?.let {
            bluetoothAdapter?.closeProfileProxy(BluetoothProfile.A2DP, it)
        }
    }

    fun getCurrentOutputJson(): JSONObject {
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val json = JSONObject()

        // 1. Check for Bluetooth A2DP
        val btDevice = devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }

        if (btDevice != null) {
            json.put("output_type", "bluetooth")
            var devName = btDevice.productName.toString().ifEmpty { "Bluetooth Headphones" }
            json.put("is_connected", true)

            var codecName = "Bluetooth A2DP"
            var sampleRate: Int? = null
            var bitDepth: Int? = null
            var bitrate: Int? = null

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 && bluetoothA2dp != null) {
                try {
                    val a2dp = bluetoothA2dp
                    val connectedDevices = a2dp?.connectedDevices
                    val activeBtDevice: BluetoothDevice? = connectedDevices?.firstOrNull()
                    if (activeBtDevice != null) {
                        try {
                            val n = activeBtDevice.name
                            if (!n.isNullOrEmpty()) {
                                devName = n
                            }
                        } catch (_: SecurityException) {}
                    }
                    if (a2dp != null && activeBtDevice != null) {
                        val getCodecStatusMethod = a2dp.javaClass.getMethod("getCodecStatus", BluetoothDevice::class.java)
                        val codecStatus = getCodecStatusMethod.invoke(a2dp, activeBtDevice)
                        if (codecStatus != null) {
                            val getCodecConfigMethod = codecStatus.javaClass.getMethod("getCodecConfig")
                            val config = getCodecConfigMethod.invoke(codecStatus)
                            if (config != null) {
                                val getCodecTypeMethod = config.javaClass.getMethod("getCodecType")
                                val codecType = (getCodecTypeMethod.invoke(config) as? Int) ?: -1

                                val getSampleRateMethod = config.javaClass.getMethod("getSampleRate")
                                val sampleRateVal = (getSampleRateMethod.invoke(config) as? Int) ?: 0

                                val getBitsMethod = config.javaClass.getMethod("getBitsPerSample")
                                val bitsVal = (getBitsMethod.invoke(config) as? Int) ?: 0

                                codecName = when (codecType) {
                                    4 -> {
                                        bitrate = 990
                                        "LDAC"
                                    }
                                    3 -> {
                                        bitrate = 576
                                        "aptX HD"
                                    }
                                    2 -> {
                                        bitrate = 352
                                        "aptX"
                                    }
                                    1 -> {
                                        bitrate = 256
                                        "AAC"
                                    }
                                    0 -> {
                                        bitrate = 328
                                        "SBC"
                                    }
                                    else -> "Bluetooth A2DP"
                                }

                                sampleRate = when (sampleRateVal) {
                                    0x1 -> 44100
                                    0x2 -> 48000
                                    0x4 -> 88200
                                    0x8 -> 96000
                                    0x10 -> 176400
                                    0x20 -> 192000
                                    else -> 48000
                                }

                                bitDepth = when (bitsVal) {
                                    0x1 -> 16
                                    0x2 -> 24
                                    0x4 -> 32
                                    else -> 16
                                }
                            }
                        }
                    }
                } catch (_: Exception) {
                    // Fallback to generic bluetooth
                }
            }

            json.put("device_name", devName)
            json.put("codec", codecName)
            if (sampleRate != null) json.put("sample_rate_hz", sampleRate)
            if (bitDepth != null) json.put("bit_depth", bitDepth)
            if (bitrate != null) json.put("bitrate_kbps", bitrate)
            return json
        }

        // 2. Check for USB DAC
        val usbDevice = devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
            it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
            it.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
        }

        if (usbDevice != null) {
            json.put("output_type", "usb_dac")
            json.put("device_name", usbDevice.productName.toString().ifEmpty { "USB DAC" })
            json.put("codec", "PCM Lossless")
            json.put("sample_rate_hz", 96000)
            json.put("bit_depth", 24)
            json.put("is_connected", true)
            return json
        }

        // 3. Check for 3.5mm Wired Headset
        val wiredDevice = devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
        }

        if (wiredDevice != null) {
            json.put("output_type", "wired")
            json.put("device_name", "Wired Headphones")
            json.put("codec", "Analog Output")
            json.put("sample_rate_hz", 48000)
            json.put("bit_depth", 24)
            json.put("is_connected", true)
            return json
        }

        // 4. Fallback to Built-in Speaker
        json.put("output_type", "builtin_speaker")
        json.put("device_name", "Phone Speaker")
        json.put("codec", "Built-in Audio")
        json.put("sample_rate_hz", 48000)
        json.put("bit_depth", 16)
        json.put("is_connected", true)
        return json
    }

    private fun dispatchCurrentOutput() {
        val json = getCurrentOutputJson()
        onOutputChanged(json)
    }
}
