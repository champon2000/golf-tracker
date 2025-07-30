package com.example.golf_tracker

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "GolfTrackerCamera"
        private const val CAMERA_PERMISSION_REQUEST_CODE = 100
        private const val CAMERA_CHANNEL = "com.example.golf_tracker/camera_stream"
        private const val CAMERA_EVENT_CHANNEL = "com.example.golf_tracker/camera_events"
        
        // Target streaming parameters
        private const val TARGET_WIDTH = 1280
        private const val TARGET_HEIGHT = 720
        private const val TARGET_FPS = 30
    }

    private lateinit var cameraExecutor: ExecutorService
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    private var camera: Camera? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalyzer: ImageAnalysis? = null
    private var isStreaming = false
    
    // Frame rate control
    private var lastFrameTime = 0L
    private val frameInterval = 1000L / TARGET_FPS
    
    // Performance monitoring
    private var frameCount = 0
    private var lastFpsTime = System.currentTimeMillis()
    private val performanceMonitor = CameraPerformanceMonitor()
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cameraExecutor = Executors.newSingleThreadExecutor()
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Setup method channel for camera control
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startCameraStream" -> {
                    val useFrontCamera = call.argument<Boolean>("useFrontCamera") ?: false
                    startCameraStream(useFrontCamera, result)
                }
                "stopCameraStream" -> {
                    stopCameraStream(result)
                }
                "switchCamera" -> {
                    val useFrontCamera = call.argument<Boolean>("useFrontCamera") ?: false
                    switchCamera(useFrontCamera, result)
                }
                "getCameraInfo" -> {
                    getCameraInfo(result)
                }
                "getPerformanceMetrics" -> {
                    getPerformanceMetrics(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Setup event channel for streaming frames
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_EVENT_CHANNEL)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }
    
    private fun startCameraStream(useFrontCamera: Boolean, result: MethodChannel.Result) {
        if (!checkCameraPermission()) {
            requestCameraPermission()
            result.error("PERMISSION_DENIED", "Camera permission not granted", null)
            return
        }
        
        if (isStreaming) {
            result.success(mapOf("status" to "already_streaming"))
            return
        }
        
        startCamera(useFrontCamera) { success ->
            if (success) {
                isStreaming = true
                result.success(mapOf(
                    "status" to "streaming_started",
                    "width" to TARGET_WIDTH,
                    "height" to TARGET_HEIGHT,
                    "fps" to TARGET_FPS
                ))
            } else {
                result.error("CAMERA_ERROR", "Failed to start camera", null)
            }
        }
    }
    
    private fun stopCameraStream(result: MethodChannel.Result) {
        stopCamera()
        isStreaming = false
        result.success(mapOf("status" to "streaming_stopped"))
    }
    
    private fun switchCamera(useFrontCamera: Boolean, result: MethodChannel.Result) {
        if (!isStreaming) {
            result.error("NOT_STREAMING", "Camera is not streaming", null)
            return
        }
        
        stopCamera()
        startCamera(useFrontCamera) { success ->
            if (success) {
                result.success(mapOf("status" to "camera_switched"))
            } else {
                isStreaming = false
                result.error("CAMERA_ERROR", "Failed to switch camera", null)
            }
        }
    }
    
    private fun getCameraInfo(result: MethodChannel.Result) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val provider = cameraProviderFuture.get()
            val hasBackCamera = provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
            val hasFrontCamera = provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
            
            result.success(mapOf(
                "hasBackCamera" to hasBackCamera,
                "hasFrontCamera" to hasFrontCamera,
                "isStreaming" to isStreaming
            ))
        }, ContextCompat.getMainExecutor(this))
    }
    
    private fun getPerformanceMetrics(result: MethodChannel.Result) {
        val metrics = performanceMonitor.getMetrics()
        result.success(mapOf(
            "currentFps" to metrics.currentFps,
            "averageFps" to metrics.averageFps,
            "droppedFramesPercent" to metrics.droppedFramesPercent,
            "averageProcessingTime" to metrics.averageProcessingTime,
            "memoryUsageMB" to metrics.memoryUsageMB,
            "peakMemoryUsageMB" to metrics.peakMemoryUsageMB
        ))
    }
    
    private fun startCamera(useFrontCamera: Boolean, callback: (Boolean) -> Unit) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                performanceMonitor.reset()
                
                // Camera selector
                val cameraSelector = if (useFrontCamera) {
                    CameraSelector.DEFAULT_FRONT_CAMERA
                } else {
                    CameraSelector.DEFAULT_BACK_CAMERA
                }
                
                // Image analysis for streaming
                imageAnalyzer = ImageAnalysis.Builder()
                    .setTargetResolution(Size(TARGET_WIDTH, TARGET_HEIGHT))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .build()
                    .also { analysis ->
                        analysis.setAnalyzer(cameraExecutor, YuvToByteArrayAnalyzer())
                    }
                
                // Unbind all use cases before rebinding
                cameraProvider?.unbindAll()
                
                // Bind use cases to camera
                camera = cameraProvider?.bindToLifecycle(
                    this,
                    cameraSelector,
                    imageAnalyzer
                )
                
                callback(true)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start camera", e)
                callback(false)
            }
        }, ContextCompat.getMainExecutor(this))
    }
    
    private fun stopCamera() {
        try {
            cameraProvider?.unbindAll()
            camera = null
            imageAnalyzer = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping camera", e)
        }
    }
    
    private inner class YuvToByteArrayAnalyzer : ImageAnalysis.Analyzer {
        private val mainHandler = Handler(Looper.getMainLooper())
        
        override fun analyze(image: ImageProxy) {
            val startTime = System.currentTimeMillis()
            
            try {
                // Frame rate limiting
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastFrameTime < frameInterval) {
                    performanceMonitor.recordDroppedFrame()
                    image.close()
                    return
                }
                lastFrameTime = currentTime
                
                // Performance monitoring
                performanceMonitor.recordFrame()
                frameCount++
                if (currentTime - lastFpsTime >= 1000) {
                    val fps = frameCount
                    frameCount = 0
                    lastFpsTime = currentTime
                    performanceMonitor.logMetrics()
                }
                
                // Convert YUV to byte array
                val data = imageToByteArray(image)
                
                // Send frame data to Flutter
                eventSink?.let { sink ->
                    mainHandler.post {
                        sink.success(mapOf(
                            "type" to "frame",
                            "data" to data,
                            "width" to image.width,
                            "height" to image.height,
                            "timestamp" to System.currentTimeMillis(),
                            "format" to "yuv420"
                        ))
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing frame", e)
                mainHandler.post {
                    eventSink?.error("FRAME_ERROR", "Error processing frame", e.message)
                }
            } finally {
                image.close()
                
                // Record processing time
                val processingTime = System.currentTimeMillis() - startTime
                performanceMonitor.recordProcessingTime(processingTime)
            }
        }
        
        private fun imageToByteArray(image: ImageProxy): ByteArray {
            val planes = image.planes
            val yPlane = planes[0]
            val uPlane = planes[1]
            val vPlane = planes[2]
            
            val ySize = yPlane.buffer.remaining()
            val uSize = uPlane.buffer.remaining()
            val vSize = vPlane.buffer.remaining()
            
            val nv21 = ByteArray(ySize + uSize + vSize)
            
            // Copy Y plane
            yPlane.buffer.get(nv21, 0, ySize)
            
            // Interleave U and V planes for NV21 format
            val uvPixelStride = uPlane.pixelStride
            if (uvPixelStride == 1) {
                // Efficient copy for packed UV planes
                uPlane.buffer.get(nv21, ySize, uSize)
                vPlane.buffer.get(nv21, ySize + uSize, vSize)
            } else {
                // Handle pixel stride for UV planes
                var pos = ySize
                val uBuffer = uPlane.buffer
                val vBuffer = vPlane.buffer
                val uvWidth = image.width / 2
                val uvHeight = image.height / 2
                
                for (row in 0 until uvHeight) {
                    for (col in 0 until uvWidth) {
                        nv21[pos++] = vBuffer.get(row * vPlane.rowStride + col * uvPixelStride)
                        nv21[pos++] = uBuffer.get(row * uPlane.rowStride + col * uvPixelStride)
                    }
                }
            }
            
            return nv21
        }
    }
    
    private fun checkCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    private fun requestCameraPermission() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST_CODE
        )
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Permission granted, notify Flutter
                methodChannel.invokeMethod("onPermissionGranted", null)
            } else {
                // Permission denied, notify Flutter
                methodChannel.invokeMethod("onPermissionDenied", null)
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopCamera()
        cameraExecutor.shutdown()
    }
}