package com.smartpoc.app.smartpoc

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.meta.wearable.dat.camera.Camera
import com.meta.wearable.dat.camera.Stream
import com.meta.wearable.dat.camera.addCamera
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import com.meta.wearable.dat.core.session.DeviceSession
import com.meta.wearable.dat.core.session.DeviceSessionState
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.RegistrationState
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity(), MethodChannel.MethodCallHandler {

    private val TAG = "SmartPocMeta"
    private val METHOD_CHANNEL = "com.smartpoc.app/meta_glasses"
    private val EVENTS_CHANNEL = "com.smartpoc.app/meta_glasses/events"
    private val FRAMES_CHANNEL = "com.smartpoc.app/meta_glasses/frames"

    // Legacy fallback channel names if needed
    private val LEGACY_METHOD_CHANNEL = "health.parrot/meta_glasses"
    private val LEGACY_EVENTS_CHANNEL = "health.parrot/meta_glasses/events"
    private val LEGACY_FRAMES_CHANNEL = "health.parrot/meta_glasses/frames"

    companion object {
        private const val PERMISSION_REQUEST_CODE = 9001
    }

    private val datScope = CoroutineScope(Dispatchers.Main + Job())
    private val mainHandler = Handler(Looper.getMainLooper())

    private var methodChannel: MethodChannel? = null
    private var legacyMethodChannel: MethodChannel? = null
    private var eventsEventSink: EventChannel.EventSink? = null
    private var framesEventSink: EventChannel.EventSink? = null

    private var datInitialized = false
    private var currentRegistrationState = "UNREGISTERED"
    private val discoveredDeviceList = mutableListOf<String>()

    private var deviceSession: DeviceSession? = null
    private var camera: Camera? = null
    private var cameraStream: Stream? = null
    private var videoStreamJob: Job? = null

    // Native Video Decoder for uploaded recorded videos
    private var videoRetriever: MediaMetadataRetriever? = null
    private var videoDurationUs: Long = 0L
    private var videoCurrentTimeUs: Long = 0L

    // Broadcast receiver for Bluetooth battery level updates
    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "android.bluetooth.device.action.BATTERY_LEVEL_CHANGED") {
                val level = intent.getIntExtra("android.bluetooth.device.extra.BATTERY_LEVEL", -1)
                if (level in 0..100) {
                    Log.i(TAG, "Bluetooth battery level changed: $level%")
                    sendEvent(mapOf("type" to "battery_level", "battery" to level))
                }
            }
        }
    }

    // Register Wearables Permission Contract for Meta View
    private val requestWearablePermissionLauncher = registerForActivityResult(
        Wearables.RequestPermissionContract()
    ) { status ->
        Log.i(TAG, "Wearables PermissionStatus result: $status")
        val isGranted = status.toString().contains("GRANTED", ignoreCase = true)
        sendEvent(mapOf("type" to "camera_permission", "granted" to isGranted, "status" to status.toString()))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler(this)

        legacyMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_METHOD_CHANNEL)
        legacyMethodChannel?.setMethodCallHandler(this)

        val eventsHandler = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventsEventSink = events
                sendEvent(mapOf("type" to "registration_state", "state" to currentRegistrationState))
                sendEvent(mapOf("type" to "devices_updated", "devices" to discoveredDeviceList))
                val battery = getGlassesBatteryLevel()
                if (battery in 0..100) {
                    sendEvent(mapOf("type" to "battery_level", "battery" to battery))
                }
            }

            override fun onCancel(arguments: Any?) {
                eventsEventSink = null
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS_CHANNEL).setStreamHandler(eventsHandler)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_EVENTS_CHANNEL).setStreamHandler(eventsHandler)

        val framesHandler = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                framesEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                framesEventSink = null
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, FRAMES_CHANNEL).setStreamHandler(framesHandler)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_FRAMES_CHANNEL).setStreamHandler(framesHandler)

        // Register Video Decoder for recorded video uploads
        val videoDecoderChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.smartpoc.app/video_decoder")
        videoDecoderChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "loadVideo" -> {
                    try {
                        val filePath = call.argument<String>("filePath")
                        if (filePath != null) {
                            try {
                                videoRetriever?.release()
                            } catch (e: Exception) {}
                            val retriever = MediaMetadataRetriever()
                            retriever.setDataSource(filePath)
                            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            val durMs = durationStr?.toLongOrNull() ?: 0L
                            videoDurationUs = durMs * 1000L
                            videoCurrentTimeUs = 0L
                            videoRetriever = retriever
                            result.success(mapOf("durationMs" to durMs))
                        } else {
                            result.error("INVALID_ARGS", "filePath is required", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error loading video in MediaMetadataRetriever: ${e.message}")
                        result.error("LOAD_ERROR", e.message, null)
                    }
                }
                "getNextFrame" -> {
                    try {
                        val retriever = videoRetriever
                        if (retriever == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        var bitmap: Bitmap? = null
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                            try {
                                bitmap = retriever.getScaledFrameAtTime(videoCurrentTimeUs, MediaMetadataRetriever.OPTION_CLOSEST, 640, 480)
                            } catch (e: Exception) {
                                bitmap = null
                            }
                        }
                        if (bitmap == null) {
                            bitmap = retriever.getFrameAtTime(videoCurrentTimeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                ?: retriever.getFrameAtTime(videoCurrentTimeUs)
                        }

                        if (bitmap != null) {
                            val finalBitmap = if (bitmap.width > 640 || bitmap.height > 480) {
                                val ratio = Math.min(640.0 / bitmap.width, 480.0 / bitmap.height)
                                val targetWidth = Math.max(1, (bitmap.width * ratio).toInt())
                                val targetHeight = Math.max(1, (bitmap.height * ratio).toInt())
                                Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
                            } else {
                                bitmap
                            }

                            val stream = ByteArrayOutputStream()
                            finalBitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
                            val jpegBytes = stream.toByteArray()

                            // Advance timestamp by 2.0s (2,000,000 us) to match live camera interval
                            videoCurrentTimeUs += 2000000L
                            if (videoDurationUs > 0 && videoCurrentTimeUs >= videoDurationUs) {
                                videoCurrentTimeUs = 0L // Loop video frames continuously
                            }
                            result.success(jpegBytes)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error extracting video frame: ${e.message}")
                        result.success(null)
                    }
                }
                "dispose" -> {
                    try {
                        videoRetriever?.release()
                        videoRetriever = null
                        videoCurrentTimeUs = 0L
                        videoDurationUs = 0L
                    } catch (e: Exception) {}
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val filter = IntentFilter("android.bluetooth.device.action.BATTERY_LEVEL_CHANGED")
            registerReceiver(batteryReceiver, filter)
        } catch (e: Exception) {
            Log.w(TAG, "Could not register battery receiver: ${e.message}")
        }
        if (hasRequiredPermissions()) {
            initializeDat()
        } else {
            requestAppPermissions()
        }
    }

    private fun hasRequiredPermissions(): Boolean {
        val audioGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val cameraGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        val btConnectGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else true
        val btScanGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else true
        return audioGranted && cameraGranted && btConnectGranted && btScanGranted
    }

    private fun requestAppPermissions() {
        val neededPermissions = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            neededPermissions.add(Manifest.permission.RECORD_AUDIO)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            neededPermissions.add(Manifest.permission.CAMERA)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            neededPermissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                neededPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                neededPermissions.add(Manifest.permission.BLUETOOTH_SCAN)
            }
        }
        if (neededPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, neededPermissions.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val audioIdx = permissions.indexOf(Manifest.permission.RECORD_AUDIO)
            if (audioIdx >= 0) {
                val audioGranted = grantResults.getOrNull(audioIdx) == PackageManager.PERMISSION_GRANTED
                sendEvent(mapOf("type" to "audio_permission", "granted" to audioGranted))
            }
            initializeDat()
        }
    }

    private fun initializeDat() {
        if (datInitialized) return
        datInitialized = true

        try {
            Wearables.initialize(this)
            Log.i(TAG, "Wearables.initialize() succeeded")
        } catch (e: Exception) {
            Log.e(TAG, "Wearables.initialize() failed", e)
            sendEvent(mapOf("type" to "error", "message" to "Wearables.initialize failed: ${e.message}"))
        }

        // Observe Devices
        datScope.launch {
            try {
                Wearables.devices.collect { devices ->
                    discoveredDeviceList.clear()
                    devices.forEach { discoveredDeviceList.add(it.toString()) }
                    sendEvent(mapOf("type" to "devices_updated", "devices" to discoveredDeviceList))

                    devices.forEach { deviceId ->
                        launch {
                            Wearables.devicesMetadata[deviceId]?.collect { device ->
                                val battery = getGlassesBatteryLevel(device.name)
                                sendEvent(
                                    mapOf(
                                        "type" to "device_metadata",
                                        "deviceId" to deviceId.toString(),
                                        "name" to device.name,
                                        "linkState" to device.linkState.name,
                                        "battery" to (if (battery in 0..100) battery else null)
                                    )
                                )
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error collecting devices", e)
            }
        }

        // Observe Registration
        datScope.launch {
            try {
                Wearables.registrationState.collect { state ->
                    currentRegistrationState = state.toString()
                    sendEvent(mapOf("type" to "registration_state", "state" to currentRegistrationState))

                    if (state == RegistrationState.AVAILABLE) {
                        try {
                            Wearables.startRegistration(this@MainActivity)
                        } catch (e: Exception) {
                            Log.e(TAG, "startRegistration failed", e)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error collecting registrationState", e)
            }
        }
    }

    private fun getGlassesBatteryLevel(targetName: String? = null): Int {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                return -1
            }
            val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter ?: return -1
            val bondedDevices = adapter.bondedDevices ?: return -1

            for (btDevice in bondedDevices) {
                val name = btDevice.name ?: ""
                if ((targetName != null && name.contains(targetName, ignoreCase = true)) ||
                    name.contains("Ray-Ban", ignoreCase = true) ||
                    name.contains("Meta", ignoreCase = true) ||
                    name.contains("hammerhead", ignoreCase = true) ||
                    name.contains("Glasses", ignoreCase = true) ||
                    name.contains("RW400", ignoreCase = true)) {
                    val level = readDeviceBattery(btDevice)
                    if (level in 0..100) return level
                }
            }

            for (btDevice in bondedDevices) {
                val level = readDeviceBattery(btDevice)
                if (level in 0..100) return level
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get battery level: ${e.message}")
        }
        return -1
    }

    private fun readDeviceBattery(btDevice: BluetoothDevice): Int {
        return try {
            val method = btDevice.javaClass.getMethod("getBatteryLevel")
            method.invoke(btDevice) as? Int ?: -1
        } catch (e: Exception) {
            -1
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startRegistration" -> {
                try {
                    try { Wearables.startUnregistration(this) } catch (ignore: Exception) {}
                    Wearables.startRegistration(this)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("REGISTRATION_ERROR", e.message, null)
                }
            }
            "startCameraStream" -> startCameraStreaming(result)
            "stopCameraStream" -> {
                stopCameraStreamingInternal()
                sendEvent(mapOf("type" to "stream_state", "state" to "STOPPED"))
                result.success(true)
            }
            "checkCameraPermission" -> checkCameraPermission(result)
            "requestCameraPermission" -> {
                mainHandler.post { requestWearablePermissionLauncher.launch(Permission.CAMERA) }
                result.success(true)
            }
            "checkMicrophonePermission" -> {
                val isGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                result.success(isGranted)
            }
            "requestMicrophonePermission" -> {
                val isGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                if (!isGranted) {
                    mainHandler.post {
                        ActivityCompat.requestPermissions(this@MainActivity, arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST_CODE)
                    }
                }
                result.success(isGranted)
            }
            "getBatteryLevel" -> {
                val battery = getGlassesBatteryLevel()
                result.success(if (battery in 0..100) battery else null)
            }
            "getDiscoveredDevices" -> result.success(discoveredDeviceList)
            else -> result.notImplemented()
        }
    }

    private fun checkCameraPermission(flutterResult: MethodChannel.Result?) {
        datScope.launch {
            try {
                Wearables.checkPermissionStatus(Permission.CAMERA)
                    .onSuccess { status ->
                        val isGranted = status.toString().contains("GRANTED", ignoreCase = true)
                        flutterResult?.success(isGranted)
                    }
                    .onFailure { error, _ ->
                        flutterResult?.error("PERMISSION_ERROR", error.toString(), null)
                    }
            } catch (e: Exception) {
                flutterResult?.error("PERMISSION_EXCEPTION", e.message, null)
            }
        }
    }

    private fun startCameraStreaming(flutterResult: MethodChannel.Result?) {
        datScope.launch {
            try {
                // 1. Verify Camera Permission
                val permResult = Wearables.checkPermissionStatus(Permission.CAMERA)
                var isGranted = false
                permResult.onSuccess { status -> isGranted = status.toString().contains("GRANTED", ignoreCase = true) }

                if (!isGranted) {
                    mainHandler.post { requestWearablePermissionLauncher.launch(Permission.CAMERA) }
                    flutterResult?.error("PERMISSION_REQUIRED", "Meta Camera permission required. Prompt opened.", null)
                    return@launch
                }

                // 2. Hardware cooldown & reset
                stopCameraStreamingInternal()
                delay(200L)

                // 3. Create Session with AutoDeviceSelector
                val sessionResult = Wearables.createSession(AutoDeviceSelector())
                sessionResult.onSuccess { session ->
                    deviceSession = session
                    session.start()

                    launch {
                        try {
                            // 4. Await DeviceSessionState.STARTED
                            withTimeout(10000L) {
                                session.state.first { it == DeviceSessionState.STARTED }
                            }

                            // 5. Add Camera with Balanced Quality (Low-latency transmission over Wi-Fi/BT)
                            val config = StreamConfiguration(videoQuality = VideoQuality.MEDIUM)
                            val addCamResult = session.addCamera(config)
                            addCamResult.onSuccess { cam ->
                                camera = cam
                                val stream = cam.stream
                                cameraStream = stream

                                stream.start().onSuccess {
                                    flutterResult?.success(true)
                                    sendEvent(mapOf("type" to "stream_state", "state" to "STREAMING"))

                                    // 6. Low-Latency Frame Processing & Concurrency-Gated Format Transposition
                                    videoStreamJob?.cancel()
                                    videoStreamJob = launch(Dispatchers.Default) {
                                        var framesSkipped = 0
                                        var lastFrameSentTimeMs = 0L
                                        val minFrameIntervalMs = 66L // ~15 FPS max for responsive real-time preview without flooding EventChannel
                                        val isProcessing = java.util.concurrent.atomic.AtomicBoolean(false)
                                        var cachedNv21: ByteArray? = null

                                        stream.videoStream.collect { videoFrame ->
                                            if (videoFrame.isCodecConfig) return@collect

                                            // Skip first 2 frames on stream start (transient/auto-exposure adjustment)
                                            if (framesSkipped < 2) {
                                                framesSkipped++
                                                return@collect
                                            }

                                            val currentTime = System.currentTimeMillis()
                                            if (currentTime - lastFrameSentTimeMs < minFrameIntervalMs) {
                                                return@collect
                                            }

                                            if (!isProcessing.compareAndSet(false, true)) {
                                                return@collect
                                            }

                                            try {
                                                val width = videoFrame.width
                                                val height = videoFrame.height
                                                val buffer = videoFrame.buffer.duplicate()
                                                buffer.rewind()
                                                val remaining = buffer.remaining()
                                                if (remaining == 0) return@collect

                                                val rawBytes = ByteArray(remaining)
                                                buffer.get(rawBytes)

                                                var displayBytes = rawBytes
                                                if (!videoFrame.isCompressed && width > 0 && height > 0) {
                                                    val ySize = width * height
                                                    val uvSize = ySize / 4
                                                    val totalNv21Size = ySize + uvSize * 2

                                                    var nv21Bytes = cachedNv21
                                                    if (nv21Bytes == null || nv21Bytes.size != totalNv21Size) {
                                                        nv21Bytes = ByteArray(totalNv21Size)
                                                        cachedNv21 = nv21Bytes
                                                    }

                                                    // Copy Y Plane (Luma)
                                                    System.arraycopy(rawBytes, 0, nv21Bytes, 0, ySize)

                                                    // Interleave U and V Planes into NV21 (VU order)
                                                    val uStart = ySize
                                                    val vStart = ySize + uvSize
                                                    var chromaIdx = ySize
                                                    for (i in 0 until uvSize) {
                                                        if (vStart + i < rawBytes.size && uStart + i < rawBytes.size) {
                                                            nv21Bytes[chromaIdx] = rawBytes[vStart + i]
                                                            nv21Bytes[chromaIdx + 1] = rawBytes[uStart + i]
                                                        }
                                                        chromaIdx += 2
                                                    }

                                                    // Fast Compress NV21 to JPEG (75% quality for quick encoding and compact payloads)
                                                    val yuvImage = YuvImage(nv21Bytes, ImageFormat.NV21, width, height, null)
                                                    val outStream = ByteArrayOutputStream(ySize / 2)
                                                    yuvImage.compressToJpeg(Rect(0, 0, width, height), 75, outStream)
                                                    displayBytes = outStream.toByteArray()
                                                }

                                                lastFrameSentTimeMs = System.currentTimeMillis()

                                                // Dispatch immutable JPEG byte array to UI
                                                withContext(Dispatchers.Main) {
                                                    framesEventSink?.success(displayBytes)
                                                }
                                            } catch (ex: Exception) {
                                                Log.e(TAG, "Frame processing error", ex)
                                            } finally {
                                                isProcessing.set(false)
                                            }
                                        }
                                    }
                                }.onFailure { streamErr, _ ->
                                    flutterResult?.error("STREAM_START_FAILED", streamErr.toString(), null)
                                }
                            }.onFailure { camErr, _ ->
                                flutterResult?.error("CAMERA_ADD_FAILED", camErr.description, null)
                            }
                        } catch (e: Exception) {
                            flutterResult?.error("SESSION_TIMEOUT", e.message, null)
                        }
                    }
                }.onFailure { sessErr, _ ->
                    flutterResult?.error("SESSION_FAILED", sessErr.description, null)
                }
            } catch (e: Exception) {
                flutterResult?.error("STREAM_EXCEPTION", e.message, null)
            }
        }
    }

    private fun stopCameraStreamingInternal() {
        try {
            videoStreamJob?.cancel()
            videoStreamJob = null
            cameraStream?.stop()
            camera?.stop()
            camera = null
            cameraStream = null
            deviceSession?.stop()
            deviceSession = null
        } catch (ignore: Exception) {}
    }

    private fun sendEvent(data: Map<String, Any?>) {
        mainHandler.post {
            eventsEventSink?.success(data)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(batteryReceiver)
        } catch (ignore: Exception) {}
        stopCameraStreamingInternal()
        datScope.cancel()
        super.onDestroy()
    }
}
