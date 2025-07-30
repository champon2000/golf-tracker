package com.example.golf_tracker

import android.content.Context
import android.graphics.*
import android.media.Image
import android.util.Log
import androidx.camera.core.ImageProxy
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.math.min

/**
 * Utility class for handling camera stream operations and image conversions
 */
class CameraStreamHandler {
    companion object {
        private const val TAG = "CameraStreamHandler"
        
        /**
         * Convert ImageProxy to JPEG byte array with optional quality and scaling
         */
        fun imageProxyToJpeg(
            imageProxy: ImageProxy,
            quality: Int = 85,
            maxWidth: Int = 1920,
            maxHeight: Int = 1080
        ): ByteArray? {
            return try {
                val bitmap = imageProxyToBitmap(imageProxy)
                val scaledBitmap = scaleBitmap(bitmap, maxWidth, maxHeight)
                
                val outputStream = ByteArrayOutputStream()
                scaledBitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
                
                bitmap.recycle()
                if (scaledBitmap != bitmap) {
                    scaledBitmap.recycle()
                }
                
                outputStream.toByteArray()
            } catch (e: Exception) {
                Log.e(TAG, "Error converting image to JPEG", e)
                null
            }
        }
        
        /**
         * Convert ImageProxy to Bitmap
         */
        private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap {
            val planes = imageProxy.planes
            val yPlane = planes[0]
            val uPlane = planes[1]
            val vPlane = planes[2]
            
            val ySize = yPlane.buffer.remaining()
            val uSize = uPlane.buffer.remaining()
            val vSize = vPlane.buffer.remaining()
            
            val nv21 = ByteArray(ySize + uSize + vSize)
            
            yPlane.buffer.get(nv21, 0, ySize)
            
            val uvPixelStride = uPlane.pixelStride
            if (uvPixelStride == 1) {
                uPlane.buffer.get(nv21, ySize, uSize)
                vPlane.buffer.get(nv21, ySize + uSize, vSize)
            } else {
                var pos = ySize
                for (i in 0 until uSize / uvPixelStride) {
                    nv21[pos] = uPlane.buffer[i * uvPixelStride]
                    nv21[pos + 1] = vPlane.buffer[i * uvPixelStride]
                    pos += 2
                }
            }
            
            val yuvImage = YuvImage(nv21, ImageFormat.NV21, imageProxy.width, imageProxy.height, null)
            val outputStream = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, imageProxy.width, imageProxy.height), 100, outputStream)
            
            val jpegData = outputStream.toByteArray()
            return BitmapFactory.decodeByteArray(jpegData, 0, jpegData.size)
        }
        
        /**
         * Scale bitmap to fit within max dimensions while maintaining aspect ratio
         */
        private fun scaleBitmap(bitmap: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
            val width = bitmap.width
            val height = bitmap.height
            
            if (width <= maxWidth && height <= maxHeight) {
                return bitmap
            }
            
            val aspectRatio = width.toFloat() / height.toFloat()
            val targetWidth: Int
            val targetHeight: Int
            
            if (width > height) {
                targetWidth = min(width, maxWidth)
                targetHeight = (targetWidth / aspectRatio).toInt()
            } else {
                targetHeight = min(height, maxHeight)
                targetWidth = (targetHeight * aspectRatio).toInt()
            }
            
            return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
        }
        
        /**
         * Calculate optimal preview size based on device capabilities
         */
        fun calculateOptimalSize(
            supportedSizes: List<Size>,
            targetWidth: Int,
            targetHeight: Int
        ): Size {
            val targetRatio = targetWidth.toFloat() / targetHeight.toFloat()
            
            return supportedSizes.minByOrNull { size ->
                val ratio = size.width.toFloat() / size.height.toFloat()
                val ratioDiff = kotlin.math.abs(ratio - targetRatio)
                val sizeDiff = kotlin.math.abs(size.width - targetWidth) + 
                               kotlin.math.abs(size.height - targetHeight)
                ratioDiff * 1000 + sizeDiff
            } ?: supportedSizes.first()
        }
        
        /**
         * Get rotation compensation for camera based on device orientation
         */
        fun getRotationCompensation(
            cameraId: String,
            activity: android.app.Activity,
            context: Context
        ): Int {
            val deviceRotation = activity.windowManager.defaultDisplay.rotation
            var rotationCompensation = ORIENTATIONS.get(deviceRotation)
            
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
            val sensorOrientation = cameraManager
                .getCameraCharacteristics(cameraId)
                .get(android.hardware.camera2.CameraCharacteristics.SENSOR_ORIENTATION)!!
            
            rotationCompensation = (rotationCompensation + sensorOrientation + 270) % 360
            
            return rotationCompensation
        }
        
        private val ORIENTATIONS = android.util.SparseIntArray().apply {
            append(android.view.Surface.ROTATION_0, 90)
            append(android.view.Surface.ROTATION_90, 0)
            append(android.view.Surface.ROTATION_180, 270)
            append(android.view.Surface.ROTATION_270, 180)
        }
    }
}