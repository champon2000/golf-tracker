package com.example.golf_tracker

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs

class MainActivityStandalone : AppCompatActivity() {
    companion object {
        private const val TAG = "GolfTrackerCamera"
        private const val CAMERA_PERMISSION_REQUEST_CODE = 100
        
        // Target streaming parameters
        private const val TARGET_WIDTH = 1280
        private const val TARGET_HEIGHT = 720
        private const val TARGET_FPS = 30
    }

    private lateinit var cameraExecutor: ExecutorService
    
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
        setContentView(R.layout.activity_main)
        cameraExecutor = Executors.newSingleThreadExecutor()
        
        Log.d(TAG, "Golf Tracker Camera standalone activity created")
        
        // Auto-start camera for testing
        if (checkCameraPermission()) {
            startCamera(false)
        } else {
            requestCameraPermission()
        }
    }
    
    private fun startCamera(useFrontCamera: Boolean) {
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
                
                isStreaming = true
                Log.d(TAG, "Camera started successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start camera", e)
            }
        }, ContextCompat.getMainExecutor(this))
    }
    
    private fun stopCamera() {
        try {
            cameraProvider?.unbindAll()
            camera = null
            imageAnalyzer = null
            isStreaming = false
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
                    Log.d(TAG, "Current FPS: $fps")
                }
                
                // Process frame here (placeholder for golf ball detection)
                // In a real implementation, you would process the image for golf ball tracking
                
            } catch (e: Exception) {
                Log.e(TAG, "Error processing frame", e)
            } finally {
                image.close()
                
                // Record processing time
                val processingTime = System.currentTimeMillis() - startTime
                performanceMonitor.recordProcessingTime(processingTime)
            }
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
                Log.d(TAG, "Camera permission granted")
                startCamera(false)
            } else {
                Log.w(TAG, "Camera permission denied")
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopCamera()
        cameraExecutor.shutdown()
    }
}