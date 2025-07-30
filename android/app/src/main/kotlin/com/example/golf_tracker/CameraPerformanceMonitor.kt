package com.example.golf_tracker

import android.os.SystemClock
import android.util.Log
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Performance monitoring for camera streaming operations
 */
class CameraPerformanceMonitor {
    companion object {
        private const val TAG = "CameraPerformance"
        private const val FPS_WINDOW_SIZE = 30
        private const val MEMORY_CHECK_INTERVAL = 5000L // 5 seconds
    }
    
    private val frameCount = AtomicInteger(0)
    private val droppedFrames = AtomicInteger(0)
    private val lastFpsCalculation = AtomicLong(0)
    private val frameTimestamps = mutableListOf<Long>()
    private val processingTimes = mutableListOf<Long>()
    
    private var lastMemoryCheck = 0L
    private var peakMemoryUsage = 0L
    
    data class PerformanceMetrics(
        val currentFps: Float,
        val averageFps: Float,
        val droppedFramesPercent: Float,
        val averageProcessingTime: Long,
        val memoryUsageMB: Long,
        val peakMemoryUsageMB: Long
    )
    
    /**
     * Record frame capture
     */
    fun recordFrame() {
        frameCount.incrementAndGet()
        
        synchronized(frameTimestamps) {
            frameTimestamps.add(SystemClock.elapsedRealtime())
            
            // Keep only recent timestamps for FPS calculation
            while (frameTimestamps.size > FPS_WINDOW_SIZE * 2) {
                frameTimestamps.removeAt(0)
            }
        }
        
        checkMemoryUsage()
    }
    
    /**
     * Record dropped frame
     */
    fun recordDroppedFrame() {
        droppedFrames.incrementAndGet()
    }
    
    /**
     * Record processing time for a frame
     */
    fun recordProcessingTime(processingTimeMs: Long) {
        synchronized(processingTimes) {
            processingTimes.add(processingTimeMs)
            
            // Keep only recent processing times
            while (processingTimes.size > FPS_WINDOW_SIZE) {
                processingTimes.removeAt(0)
            }
        }
    }
    
    /**
     * Calculate current performance metrics
     */
    fun getMetrics(): PerformanceMetrics {
        val now = SystemClock.elapsedRealtime()
        
        // Calculate current FPS
        val currentFps = synchronized(frameTimestamps) {
            if (frameTimestamps.size < 2) {
                0f
            } else {
                val recentTimestamps = frameTimestamps.takeLast(FPS_WINDOW_SIZE)
                if (recentTimestamps.size < 2) {
                    0f
                } else {
                    val duration = recentTimestamps.last() - recentTimestamps.first()
                    if (duration > 0) {
                        (recentTimestamps.size - 1) * 1000f / duration
                    } else {
                        0f
                    }
                }
            }
        }
        
        // Calculate average FPS over lifetime
        val totalFrames = frameCount.get()
        val lifetime = now - lastFpsCalculation.get()
        val averageFps = if (lifetime > 0) {
            totalFrames * 1000f / lifetime
        } else {
            0f
        }
        
        // Calculate dropped frames percentage
        val droppedFramesPercent = if (totalFrames > 0) {
            droppedFrames.get() * 100f / totalFrames
        } else {
            0f
        }
        
        // Calculate average processing time
        val averageProcessingTime = synchronized(processingTimes) {
            if (processingTimes.isEmpty()) {
                0L
            } else {
                processingTimes.average().toLong()
            }
        }
        
        // Get memory usage
        val runtime = Runtime.getRuntime()
        val usedMemory = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
        
        return PerformanceMetrics(
            currentFps = currentFps,
            averageFps = averageFps,
            droppedFramesPercent = droppedFramesPercent,
            averageProcessingTime = averageProcessingTime,
            memoryUsageMB = usedMemory,
            peakMemoryUsageMB = peakMemoryUsage / (1024 * 1024)
        )
    }
    
    /**
     * Reset all metrics
     */
    fun reset() {
        frameCount.set(0)
        droppedFrames.set(0)
        lastFpsCalculation.set(SystemClock.elapsedRealtime())
        
        synchronized(frameTimestamps) {
            frameTimestamps.clear()
        }
        
        synchronized(processingTimes) {
            processingTimes.clear()
        }
        
        peakMemoryUsage = 0L
    }
    
    /**
     * Log current performance metrics
     */
    fun logMetrics() {
        val metrics = getMetrics()
        Log.i(TAG, """
            Camera Performance:
            - Current FPS: ${metrics.currentFps}
            - Average FPS: ${metrics.averageFps}
            - Dropped Frames: ${metrics.droppedFramesPercent}%
            - Avg Processing Time: ${metrics.averageProcessingTime}ms
            - Memory Usage: ${metrics.memoryUsageMB}MB
            - Peak Memory: ${metrics.peakMemoryUsageMB}MB
        """.trimIndent())
    }
    
    private fun checkMemoryUsage() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastMemoryCheck > MEMORY_CHECK_INTERVAL) {
            lastMemoryCheck = now
            
            val runtime = Runtime.getRuntime()
            val usedMemory = runtime.totalMemory() - runtime.freeMemory()
            if (usedMemory > peakMemoryUsage) {
                peakMemoryUsage = usedMemory
            }
            
            // Log warning if memory usage is high
            val usedMemoryMB = usedMemory / (1024 * 1024)
            val maxMemoryMB = runtime.maxMemory() / (1024 * 1024)
            val usagePercent = (usedMemoryMB * 100) / maxMemoryMB
            
            if (usagePercent > 80) {
                Log.w(TAG, "High memory usage: ${usedMemoryMB}MB / ${maxMemoryMB}MB (${usagePercent}%)")
            }
        }
    }
}