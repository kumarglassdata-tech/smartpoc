package com.smartpoc.app.smartpoc

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
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
        private const val BT_PERMISSION_REQUEST_CODE = 9001
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
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (hasBluetoothPermissions()) {
            initializeDat()
        } else {
            requestBluetoothPermissions()
        }
    }

    private fun hasBluetoothPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val connectGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        val scanGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        return connectGranted && scanGranted
    }

    private fun requestBluetoothPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val neededPermissions = mutableListOf<String>()
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                neededPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                neededPermissions.add(Manifest.permission.BLUETOOTH_SCAN)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                neededPermissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            if (neededPermissions.isNotEmpty()) {
                ActivityCompat.requestPermissions(this, neededPermissions.toTypedArray(), BT_PERMISSION_REQUEST_CODE)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BT_PERMISSION_REQUEST_CODE && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
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
                                sendEvent(
                                    mapOf(
                                        "type" to "device_metadata",
                                        "deviceId" to deviceId.toString(),
                                        "name" to device.name,
                                        "linkState" to device.linkState.name
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
            "checkCameraPermission" -> checkPermission(Permission.CAMERA, result)
            "requestCameraPermission" -> {
                mainHandler.post { requestWearablePermissionLauncher.launch(Permission.CAMERA) }
                result.success(true)
            }
            "checkMicrophonePermission" -> checkPermission(Permission.MICROPHONE, result)
            "requestMicrophonePermission" -> {
                mainHandler.post { requestWearablePermissionLauncher.launch(Permission.MICROPHONE) }
                result.success(true)
            }
            "getDiscoveredDevices" -> result.success(discoveredDeviceList)
            else -> result.notImplemented()
        }
    }

    private fun checkPermission(permission: Permission, flutterResult: MethodChannel.Result?) {
        datScope.launch {
            try {
                Wearables.checkPermissionStatus(permission)
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

                            // 5. Add Camera with High Quality @ 30 FPS
                            val config = StreamConfiguration(videoQuality = VideoQuality.HIGH)
                            val addCamResult = session.addCamera(config)
                            addCamResult.onSuccess { cam ->
                                camera = cam
                                val stream = cam.stream
                                cameraStream = stream

                                stream.start().onSuccess {
                                    flutterResult?.success(true)
                                    sendEvent(mapOf("type" to "stream_state", "state" to "STREAMING"))

                                    // 6. Synchronous Frame Processing & Format Transposition
                                    videoStreamJob?.cancel()
                                    videoStreamJob = launch(Dispatchers.Default) {
                                        stream.videoStream.collect { videoFrame ->
                                            if (videoFrame.isCodecConfig) return@collect

                                            val width = videoFrame.width
                                            val height = videoFrame.height
                                            val buffer = videoFrame.buffer.duplicate()
                                            buffer.rewind()
                                            val remaining = buffer.remaining()
                                            if (remaining == 0) return@collect

                                            // A. SYNCHRONOUS COPY: Prevents JNI buffer reuse corruption
                                            val rawBytes = ByteArray(remaining)
                                            buffer.get(rawBytes)

                                            // B. PLANAR I420 -> INTERLEAVED NV21 TRANSPOSITION
                                            var displayBytes = rawBytes
                                            if (!videoFrame.isCompressed && width > 0 && height > 0) {
                                                try {
                                                    val ySize = width * height
                                                    val uvSize = ySize / 4
                                                    val nv21Bytes = ByteArray(ySize + uvSize * 2)

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

                                                    // Fast Compress NV21 to JPEG
                                                    val yuvImage = YuvImage(nv21Bytes, ImageFormat.NV21, width, height, null)
                                                    val outStream = ByteArrayOutputStream()
                                                    yuvImage.compressToJpeg(Rect(0, 0, width, height), 80, outStream)
                                                    displayBytes = outStream.toByteArray()
                                                } catch (ex: Exception) {
                                                    displayBytes = rawBytes
                                                }
                                            }

                                            // C. Dispatch immutable JPEG byte array to UI
                                            withContext(Dispatchers.Main) {
                                                framesEventSink?.success(displayBytes)
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
        stopCameraStreamingInternal()
        datScope.cancel()
        super.onDestroy()
    }
}
