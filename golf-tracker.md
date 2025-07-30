# 手機單鏡頭高爾夫擊球追蹤 App 專案骨架

這是一個使用 Flutter 3.22 (Dart 3.4) 開發的「手機單鏡頭高爾夫擊球追蹤」App 的專案骨架。

## 1. 專案結構


.
├── android
│   ├── app
│   └── src
├── assets
│   ├── icons
│   └── models
├── ios
│   ├── Classes
│   └── Runner
├── lib
│   ├── screens
│   ├── services
│   └── widgets
├── scripts
└── pubspec.yaml


## 2. 檔案內容

---

### `pubspec.yaml`

```yaml
name: golf_tracker
description: A mobile single-lens golf shot tracking app.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

version: 1.0.0+1

environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  camera: ^0.11.0+1 # 用於 Flutter 端相機預覽控制
  tflite_flutter: ^0.10.0 # 用於載入和執行 TFLite 模型
  flutter_isolate: ^2.0.4 # 用於在獨立的 Isolate 中執行 AI 推論和計算
  sqflite: ^2.3.3+1 # 用於本地數據庫儲存
  path_provider: ^2.1.3 # 用於獲取文件系統路徑
  fl_chart: ^0.68.0 # 用於繪製圖表

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true

  assets:
    - assets/models/golfclub_ball_yolov8n.tflite
    - assets/icons/

android/app/build.gradle
// android/app/build.gradle
def flutterRoot = localProperties.getProperty('flutter.sdk')
if (flutterRoot == null) {
    throw new GradleException("Flutter SDK not found. Define location with flutter.sdk in the local.properties file.")
}

plugins {
    id "com.android.application"
    id "kotlin-android"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.example.golf_tracker"
    compileSdk flutter.compileSdkVersion
    ndkVersion flutter.ndkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = '1.8'
    }

    sourceSets {
        main.java.srcDirs += 'src/main/kotlin'
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID ([https://developer.android.com/tools/build-tools/application-id.html](https://developer.android.com/tools/build-tools/application-id.html)).
        applicationId "com.example.golf_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: [https://docs.flutter.dev/deployment/android#reviewing-the-build-configuration](https://docs.flutter.dev/deployment/android#reviewing-the-build-configuration).
        minSdk flutter.minSdkVersion
        targetSdk flutter.targetSdkVersion
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName

        // 啟用 NDK 並指定 ABI 過濾器，以支援 TFLite GPU delegate
        ndk {
            abiFilters "arm64-v8a" // 推薦使用 arm64-v8a 進行生產環境部署
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig signingConfigs.debug
        }
    }
}

flutter {
    source '../..'
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk8:$kotlin_version"
    implementation "androidx.camera:camera-camera2:1.3.3"
    implementation "androidx.camera:camera-lifecycle:1.3.3"
    implementation "androidx.camera:camera-view:1.3.3"

    // TFLite GPU delegate for Android
    implementation 'org.tensorflow:tensorflow-lite-gpu:2.16.0' # 確保版本與 tflite_flutter 相容
}

ios/Podfile
# ios/Podfile
# Podfile for Flutter project

# Uncomment this line to define a global platform for your project
platform :ios, '16.0' # 設定 iOS 平台版本為 16.0

# Flutter will use this value to locate your local development assets
flutter_application_path = '../.ios/Flutter'
load File.join(flutter_application_path, 'Flutter.podspec')

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  # Pods for Flutter
  pod 'Firebase/Core' # 範例：如果未來需要 Firebase
  pod 'TensorFlowLiteSwift' # TFLite Swift 綁定
  pod 'TensorFlowLiteSelectTfOps' # 選擇性操作，可能需要
  pod 'TensorFlowLiteGpuDelegate' # TFLite GPU Delegate

  # Add any other pods you need for your iOS project
  # For example, for Camera (AVCaptureDevice)
  # No specific pod needed for AVCaptureDevice itself, it's part of AVFoundation framework.

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      # 確保 Swift 版本設定正確
      config.build_settings['SWIFT_VERSION'] = '5.0'
      # 確保相機權限描述已在 Info.plist 中添加
      # Privacy - Camera Usage Description
    end
  end
end

ios/Classes/CameraStream.swift
// ios/Classes/CameraStream.swift
import Flutter
import UIKit
import AVFoundation

class CameraStream: NSObject, FlutterStreamHandler, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var eventSink: FlutterEventSink?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera_session_queue")

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        startCamera()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopCamera()
        eventSink = nil
        return nil
    }

    // MARK: - Camera Setup

    private func startCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession = AVCaptureSession()
            guard let captureSession = self.captureSession else { return }

            // 設置會話預設為高解析度
            captureSession.sessionPreset = .high

            // 尋找後置廣角相機
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                self.eventSink?("Camera not found")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }

                self.videoOutput = AVCaptureVideoDataOutput()
                guard let videoOutput = self.videoOutput else { return }

                // 設置像素格式為 YUV_420 (kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
                videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]

                if captureSession.canAddOutput(videoOutput) {
                    captureSession.addOutput(videoOutput)
                }

                // 嘗試設定 240 fps
                self.configure240Fps(for: camera)

                captureSession.startRunning()
                print("Camera session started with preset: \(captureSession.sessionPreset.rawValue)")
            } catch {
                self.eventSink?("Error setting up camera: \(error.localizedDescription)")
            }
        }
    }

    private func stopCamera() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
            self?.videoOutput = nil
            print("Camera session stopped.")
        }
    }

    private func configure240Fps(for device: AVCaptureDevice) {
        let desiredFps = 240.0
        var bestFormat: AVCaptureDevice.Format?
        var bestFrameRateRange: AVFrameRateRange?
        var bestScore = 0.0

        for format in device.formats {
            // 檢查像素格式是否為 YUV420
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                  pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
                continue
            }

            let ranges = format.videoSupportedFrameRateRanges
            for range in ranges {
                if range.maxFrameRate >= desiredFps {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    
                    // 計算格式分數：優先考慮240fps支援和合理解析度
                    let fpsScore = min(range.maxFrameRate / desiredFps, 1.0)
                    let resolutionScore = min(Double(dimensions.width * dimensions.height) / (1280.0 * 720.0), 2.0)
                    let score = fpsScore * 2.0 + resolutionScore // 優先考慮幀率
                    
                    if score > bestScore && dimensions.width >= 720 && dimensions.height >= 480 {
                        bestFormat = format
                        bestFrameRateRange = range
                        bestScore = score
                    }
                }
            }
        }

        guard let format = bestFormat, let range = bestFrameRateRange else {
            print("Warning: 240 fps YUV420 format not found. Trying fallback...")
            configureFallbackFormat(for: device)
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            
            let frameDuration = CMTimeMake(value: 1, timescale: Int32(min(desiredFps, range.maxFrameRate)))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            
            // 優化其他相機設定以提高效能
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
            let actualFps = min(desiredFps, range.maxFrameRate)
            print("Set camera to \(actualFps) fps with format: \(format)")
        } catch {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func configureFallbackFormat(for device: AVCaptureDevice) {
        // 尋找最高幀率的 YUV420 格式作為備選
        var fallbackFormat: AVCaptureDevice.Format?
        var maxFps = 0.0
        
        for format in device.formats {
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                  pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
                continue
            }
            
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate > maxFps {
                    fallbackFormat = format
                    maxFps = range.maxFrameRate
                }
            }
        }
        
        if let format = fallbackFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                let frameDuration = CMTimeMake(value: 1, timescale: Int32(maxFps))
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
                device.unlockForConfiguration()
                print("Using fallback format with \(maxFps) fps")
            } catch {
                print("Failed to configure fallback format: \(error)")
            }
        }
    }

    // MARK: - Buffer Pool for Memory Management
    private let bufferQueue = DispatchQueue(label: "buffer_queue", qos: .userInteractive)
    private var bufferPool: [Data] = []
    private let maxPoolSize = 5
    private var frameCount = 0
    private let frameSampleRate = 4 // 只處理每第4幀以降低CPU負載

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        
        // 降採樣：只處理部分幀以維持效能
        guard frameCount % frameSampleRate == 0 else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 驗證像素格式
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            print("Unsupported pixel format: \(pixelFormat)")
            return
        }

        bufferQueue.async { [weak self] in
            self?.processPixelBuffer(pixelBuffer)
        }
    }
    
    private func processPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        // 鎖定像素緩衝區
        let lockFlags = CVPixelBufferLockFlags.readOnly
        guard CVPixelBufferLockBaseAddress(pixelBuffer, lockFlags) == kCVReturnSuccess else {
            return
        }
        
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, lockFlags)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // 獲取 Y 平面數據
        guard let yPlaneBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let yPlaneBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let yPlaneHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

        // 獲取 UV 平面數據 (對於 NV12 格式)
        guard let uvPlaneBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else { return }
        let uvPlaneBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let uvPlaneHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

        // 計算實際需要的數據大小（考慮 stride）
        let yDataSize = width * height
        let uvDataSize = width * height / 2 // UV平面大小為Y平面的一半
        let totalSize = yDataSize + uvDataSize

        // 從緩衝池獲取或創建新的 Data 物件
        var data = getBufferFromPool(size: totalSize)
        
        // 優化的數據複製：考慮 stride
        data.withUnsafeMutableBytes { bytes in
            let dataPtr = bytes.bindMemory(to: UInt8.self).baseAddress!
            
            // 複製 Y 平面數據，處理 stride
            if yPlaneBytesPerRow == width {
                // 沒有 padding，直接複製
                memcpy(dataPtr, yPlaneBaseAddress, yDataSize)
            } else {
                // 有 padding，逐行複製
                for row in 0..<height {
                    let srcOffset = row * yPlaneBytesPerRow
                    let dstOffset = row * width
                    memcpy(dataPtr + dstOffset, yPlaneBaseAddress + srcOffset, width)
                }
            }
            
            // 複製 UV 平面數據
            let uvDestPtr = dataPtr + yDataSize
            if uvPlaneBytesPerRow == width {
                memcpy(uvDestPtr, uvPlaneBaseAddress, uvDataSize)
            } else {
                for row in 0..<(height / 2) {
                    let srcOffset = row * uvPlaneBytesPerRow
                    let dstOffset = row * width
                    memcpy(uvDestPtr + dstOffset, uvPlaneBaseAddress + srcOffset, width)
                }
            }
        }

        // 將數據和元數據發送到 Flutter
        let frameData: [String: Any] = [
            "width": width,
            "height": height,
            "bytesPerRow": width, // 標準化後的 bytesPerRow
            "uvBytesPerRow": width, // UV 平面的 bytesPerRow
            "buffer": FlutterStandardTypedData(bytes: data)
        ]

        // 使用背景執行緒發送以避免阻塞主執行緒
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(frameData)
        }
        
        // 將緩衝區歸還到池中
        returnBufferToPool(data)
    }
    
    private func getBufferFromPool(size: Int) -> Data {
        if let buffer = bufferPool.popLast(), buffer.count == size {
            return buffer
        }
        return Data(count: size)
    }
    
    private func returnBufferToPool(_ buffer: Data) {
        guard bufferPool.count < maxPoolSize else { return }
        bufferPool.append(buffer)
    }
}

// 註冊 CameraStream 類別到 Flutter
public class SwiftGolfTrackerPlugin: NSObject, FlutterPlugin {
    private static var cameraStream: CameraStream?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        // 初始化 CameraStream 實例
        let instance = SwiftGolfTrackerPlugin()
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "com.example.golf_tracker/camera_control", binaryMessenger: registrar.messenger()))
        
        // 註冊 EventChannel
        cameraStream = CameraStream()
        let eventChannel = FlutterEventChannel(name: "com.example.golf_tracker/camera_stream", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(cameraStream)
        
        // 監聽應用生命週期以管理相機資源
        registrar.addApplicationDelegate(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCamera":
            checkCameraPermissionAndStart(result: result)
        case "stopCamera":
            stopCameraStream(result: result)
        case "checkCameraPermission":
            result(checkCameraPermission())
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func checkCameraPermissionAndStart(result: @escaping FlutterResult) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            result("Camera permission granted")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        result("Camera permission granted")
                    } else {
                        result(FlutterError(code: "PERMISSION_DENIED", 
                                          message: "Camera permission denied", 
                                          details: nil))
                    }
                }
            }
        case .denied, .restricted:
            result(FlutterError(code: "PERMISSION_DENIED", 
                              message: "Camera permission denied or restricted", 
                              details: nil))
        @unknown default:
            result(FlutterError(code: "PERMISSION_UNKNOWN", 
                              message: "Unknown camera permission status", 
                              details: nil))
        }
    }
    
    private func stopCameraStream(result: @escaping FlutterResult) {
        SwiftGolfTrackerPlugin.cameraStream?.stopCamera()
        result("Camera stopped")
    }
    
    private func checkCameraPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
}

// MARK: - Application Lifecycle Delegate
extension SwiftGolfTrackerPlugin: FlutterApplicationLifeCycleDelegate {
    public func applicationDidEnterBackground(_ application: UIApplication) {
        // 應用進入背景時暫停相機以節省資源
        SwiftGolfTrackerPlugin.cameraStream?.stopCamera()
    }
    
    public func applicationWillEnterForeground(_ application: UIApplication) {
        // 應用即將進入前景時恢復相機（如果有權限）
        if checkCameraPermission() {
            // 相機會在用戶開始監聽流時自動重啟
        }
    }
    
    public func applicationWillTerminate(_ application: UIApplication) {
        // 應用終止時清理資源
        SwiftGolfTrackerPlugin.cameraStream?.stopCamera()
        SwiftGolfTrackerPlugin.cameraStream = nil
    }
}

android/src/main/kotlin/com/example/golf_tracker/CameraStream.kt
// android/src/main/kotlin/com/example/golf_tracker/CameraStream.kt
package com.example.golf_tracker

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.util.Log
import android.util.Size
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class CameraStream(private val context: Context, private val lifecycleOwner: LifecycleOwner) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null

    companion object {
        private const val TAG = "CameraStream"
        private const val TARGET_FPS = 240
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
        startCamera()
    }

    override fun onCancel(arguments: Any?) {
        stopCamera()
        eventSink = null
    }

    // Buffer pool for memory management
    private val bufferPool = mutableListOf<ByteArray>()
    private val maxPoolSize = 5
    private var frameCount = 0
    private val frameSampleRate = 4 // 只處理每第4幀以降低CPU負載

    @SuppressLint("UnsafeOptInUsageError")
    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()
            val preview = Preview.Builder().build()

            // 設置 ImageAnalysis，優化為240fps
            imageAnalysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(1280, 720)) // 高解析度
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setImageQueueDepth(1) // 確保只處理最新幀
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .build()

            // 配置240fps（如果支援）
            val camera2Config = Camera2Interop.Extender(imageAnalysis!!)
            
            // 設定多個FPS範圍選項，以便找到最佳匹配
            val fpsRanges = arrayOf(
                android.util.Range(TARGET_FPS, TARGET_FPS),      // 240fps
                android.util.Range(120, 240),                   // 120-240fps
                android.util.Range(60, 120),                    // 60-120fps
                android.util.Range(30, 60)                      // 30-60fps fallback
            )
            
            for (range in fpsRanges) {
                try {
                    camera2Config.setCaptureRequestOption(
                        android.hardware.camera2.CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                        range
                    )
                    Log.d(TAG, "Set FPS range: $range")
                    break
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to set FPS range $range: ${e.message}")
                }
            }

            imageAnalysis?.setAnalyzer(cameraExecutor) { imageProxy ->
                frameCount++
                
                // 降採樣：只處理部分幀以維持效能
                if (frameCount % frameSampleRate != 0) {
                    imageProxy.close()
                    return@setAnalyzer
                }

                processImageProxy(imageProxy)
            }

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                cameraProvider?.unbindAll()
                cameraProvider?.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    preview,
                    imageAnalysis
                )
                Log.d(TAG, "CameraX started with target FPS: $TARGET_FPS")
            } catch (exc: Exception) {
                Log.e(TAG, "Use case binding failed", exc)
                eventSink?.error("CAMERA_ERROR", "Failed to bind camera use cases: ${exc.localizedMessage}", null)
            }

        }, ContextCompat.getMainExecutor(context))
    }

    private fun processImageProxy(imageProxy: ImageProxy) {
        if (imageProxy.format != ImageFormat.YUV_420_888) {
            Log.w(TAG, "Unsupported image format: ${imageProxy.format}")
            imageProxy.close()
            return
        }

        try {
            val nv12Data = convertYuv420ToNv12(imageProxy)
            
            val frameData = mapOf(
                "width" to imageProxy.width,
                "height" to imageProxy.height,
                "bytesPerRow" to imageProxy.width, // 標準化後的 bytesPerRow
                "uvBytesPerRow" to imageProxy.width, // UV 平面的 bytesPerRow
                "buffer" to nv12Data
            )
            
            eventSink?.success(frameData)
            returnBufferToPool(nv12Data)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to process image: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    private fun convertYuv420ToNv12(imageProxy: ImageProxy): ByteArray {
        val planes = imageProxy.planes
        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        
        val width = imageProxy.width
        val height = imageProxy.height
        
        // 計算所需的緩衝區大小
        val ySize = width * height
        val uvSize = width * height / 2
        val totalSize = ySize + uvSize
        
        // 從緩衝池獲取或創建新的緩衝區
        val nv12Data = getBufferFromPool(totalSize)
        
        // 複製 Y 平面數據
        val yBuffer = yPlane.buffer
        val yRowStride = yPlane.rowStride
        val yPixelStride = yPlane.pixelStride
        
        var yIndex = 0
        for (row in 0 until height) {
            for (col in 0 until width) {
                nv12Data[yIndex++] = yBuffer[row * yRowStride + col * yPixelStride]
            }
        }
        
        // 轉換和交錯 UV 平面數據
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val uRowStride = uPlane.rowStride
        val vRowStride = vPlane.rowStride
        val uPixelStride = uPlane.pixelStride
        val vPixelStride = vPlane.pixelStride
        
        var uvIndex = ySize
        val uvHeight = height / 2
        val uvWidth = width / 2
        
        for (row in 0 until uvHeight) {
            for (col in 0 until uvWidth) {
                val uValue = uBuffer[row * uRowStride + col * uPixelStride]
                val vValue = vBuffer[row * vRowStride + col * vPixelStride]
                
                // NV12 格式：UV 交錯 (UVUVUV...)
                nv12Data[uvIndex++] = uValue
                nv12Data[uvIndex++] = vValue
            }
        }
        
        return nv12Data
    }
    
    @Synchronized
    private fun getBufferFromPool(size: Int): ByteArray {
        val buffer = bufferPool.find { it.size == size }
        if (buffer != null) {
            bufferPool.remove(buffer)
            return buffer
        }
        return ByteArray(size)
    }
    
    @Synchronized
    private fun returnBufferToPool(buffer: ByteArray) {
        if (bufferPool.size < maxPoolSize) {
            bufferPool.add(buffer)
        }
    }

    private fun stopCamera() {
        cameraProvider?.unbindAll()
        cameraExecutor.shutdown()
        Log.d(TAG, "CameraX stopped.")
    }
}

// FlutterPlugin 實現
class GolfTrackerPlugin : FlutterPlugin, LifecycleOwner, FlutterPlugin.FlutterPluginBinding.ActivityPluginBinding {
    private lateinit var applicationContext: Context
    private var cameraStream: CameraStream? = null
    private val lifecycle = CameraLifecycle()
    private var eventChannel: EventChannel? = null
    private var methodChannel: MethodChannel? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext

        // 註冊 EventChannel
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "com.example.golf_tracker/camera_stream")
        cameraStream = CameraStream(applicationContext, this)
        eventChannel?.setStreamHandler(cameraStream)

        // 註冊 MethodChannel
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.example.golf_tracker/camera_control")
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startCamera" -> {
                    try {
                        lifecycle.onStart()
                        lifecycle.onResume()
                        result.success("Camera started")
                    } catch (e: Exception) {
                        result.error("CAMERA_ERROR", "Failed to start camera: ${e.message}", null)
                    }
                }
                "stopCamera" -> {
                    try {
                        lifecycle.onPause()
                        lifecycle.onStop()
                        result.success("Camera stopped")
                    } catch (e: Exception) {
                        result.error("CAMERA_ERROR", "Failed to stop camera: ${e.message}", null)
                    }
                }
                "checkCameraPermission" -> {
                    val hasPermission = checkCameraPermission()
                    result.success(hasPermission)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // 監聽 Flutter 引擎生命週期
        lifecycle.onCreate()
        lifecycle.onStart()
        lifecycle.onResume()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        lifecycle.onPause()
        lifecycle.onStop()
        lifecycle.onDestroy()
        
        cameraStream = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }

    private fun checkCameraPermission(): Boolean {
        return androidx.core.content.ContextCompat.checkSelfPermission(
            applicationContext,
            android.Manifest.permission.CAMERA
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    // LifecycleOwner 實現，用於 CameraX
    override val lifecycle: androidx.lifecycle.Lifecycle
        get() = this.lifecycle

    class CameraLifecycle : androidx.lifecycle.Lifecycle() {
        private val observers = mutableSetOf<LifecycleObserver>()
        private var _currentState = State.INITIALIZED

        override fun getCurrentState(): State = _currentState

        override fun addObserver(observer: LifecycleObserver) {
            observers.add(observer)
        }

        override fun removeObserver(observer: LifecycleObserver) {
            observers.remove(observer)
        }

        fun onCreate() {
            _currentState = State.CREATED
            notifyObservers(Event.ON_CREATE)
            Log.d("CameraLifecycle", "onCreate: $currentState")
        }

        fun onStart() {
            _currentState = State.STARTED
            notifyObservers(Event.ON_START)
            Log.d("CameraLifecycle", "onStart: $currentState")
        }

        fun onResume() {
            _currentState = State.RESUMED
            notifyObservers(Event.ON_RESUME)
            Log.d("CameraLifecycle", "onResume: $currentState")
        }

        fun onPause() {
            _currentState = State.STARTED
            notifyObservers(Event.ON_PAUSE)
            Log.d("CameraLifecycle", "onPause: $currentState")
        }

        fun onStop() {
            _currentState = State.CREATED
            notifyObservers(Event.ON_STOP)
            Log.d("CameraLifecycle", "onStop: $currentState")
        }

        fun onDestroy() {
            _currentState = State.DESTROYED
            notifyObservers(Event.ON_DESTROY)
            Log.d("CameraLifecycle", "onDestroy: $currentState")
        }

        private fun notifyObservers(event: Event) {
            observers.forEach { observer ->
                try {
                    when (event) {
                        Event.ON_CREATE -> (observer as? DefaultLifecycleObserver)?.onCreate(this@CameraLifecycle)
                        Event.ON_START -> (observer as? DefaultLifecycleObserver)?.onStart(this@CameraLifecycle)
                        Event.ON_RESUME -> (observer as? DefaultLifecycleObserver)?.onResume(this@CameraLifecycle)
                        Event.ON_PAUSE -> (observer as? DefaultLifecycleObserver)?.onPause(this@CameraLifecycle)
                        Event.ON_STOP -> (observer as? DefaultLifecycleObserver)?.onStop(this@CameraLifecycle)
                        Event.ON_DESTROY -> (observer as? DefaultLifecycleObserver)?.onDestroy(this@CameraLifecycle)
                        else -> {}
                    }
                } catch (e: Exception) {
                    Log.e("CameraLifecycle", "Error notifying observer: ${e.message}")
                }
            }
        }
    }
}

lib/main.dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:golf_tracker/screens/practice_screen.dart';
import 'package:golf_tracker/services/database_service.dart'; // 引入數據庫服務

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.instance.database; // 初始化數據庫
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '高爾夫擊球追蹤',
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    PracticeScreen(), // 練習模式，包含相機預覽和 HUD
    Text('歷史數據頁面', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)), // TODO: 替換為實際的歷史數據頁面
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('高爾夫擊球追蹤'),
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.golf_course),
            label: '練習',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: '歷史',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber[800],
        onTap: _onItemTapped,
      ),
    );
  }
}

lib/services/tflite_service.dart
// lib/services/tflite_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class TFLiteService {
  late Interpreter _interpreter;
  late List<List<int>> _inputShape;
  late List<List<int>> _outputShape;
  late TfLiteType _inputType;
  late TfLiteType _outputType;

  // 初始化模型
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/golfclub_ball_yolov8n.tflite',
        options: InterpreterOptions()..addDelegate(GpuDelegateV2()), // 使用 GPU delegate
      );

      // 獲取輸入和輸出張量的形狀和類型
      _inputShape = _interpreter.getInputTensors().map((tensor) => tensor.shape).toList();
      _outputShape = _interpreter.getOutputTensors().map((tensor) => tensor.shape).toList();
      _inputType = _interpreter.getInputTensors().first.type;
      _outputType = _interpreter.getOutputTensors().first.type;

      print('模型載入成功！');
      print('輸入形狀: $_inputShape, 輸入類型: $_inputType');
      print('輸出形狀: $_outputShape, 輸出類型: $_outputType');
    } catch (e) {
      print('載入模型失敗: $e');
      rethrow;
    }
  }

  // 執行推論
  // 接收 YUV_420 格式的 Uint8List 數據
  List<BoundingBox>? runInference(Uint8List yuvBytes, int width, int height) {
    if (_interpreter == null) {
      print('模型尚未載入。');
      return null;
    }

    // TODO: 將 YUV_420 數據轉換為模型所需的 RGB 或灰度圖像
    // 這裡需要將 YUV 數據轉換為 Image 庫的 Image 物件，然後再縮放和正規化。
    // 這是一個複雜的過程，這裡僅提供骨架。
    // 假設我們將 Y 平面作為灰度圖像處理，並調整大小以匹配模型輸入。

    // 獲取 Y 平面數據 (簡單處理，實際應考慮 UV 平面)
    final int ySize = width * height;
    final Uint8List yBuffer = yuvBytes.sublist(0, ySize);

    // 創建一個灰度圖像
    final img.Image image = img.Image.fromBytes(width: width, height: height, bytes: yBuffer.buffer, format: img.Format.luminance);

    // 調整圖像大小以匹配模型輸入尺寸 (例如 640x640 for YOLOv8n)
    final int inputWidth = _inputShape[0][1]; // 通常是 [1, W, H, C] 或 [1, C, W, H]
    final int inputHeight = _inputShape[0][2];
    final img.Image resizedImage = img.copyResize(image, width: inputWidth, height: inputHeight);

    // 將圖像數據轉換為 Float32List (正規化到 0-1)
    final input = Float32List(1 * inputWidth * inputHeight * 3); // 假設模型需要 RGB 輸入
    int pixelIndex = 0;
    for (int y = 0; y < inputHeight; y++) {
      for (int x = 0; x < inputWidth; x++) {
        final img.Pixel pixel = resizedImage.getPixel(x, y);
        // 對於灰度圖像，R, G, B 值相同
        input[pixelIndex++] = img.getRed(pixel) / 255.0;
        input[pixelIndex++] = img.getGreen(pixel) / 255.0;
        input[pixelIndex++] = img.getBlue(pixel) / 255.0;
      }
    }

    // 準備輸入和輸出緩衝區
    final inputBuffer = Float32List.fromList(input.buffer.asFloat32List());
    // 輸出張量通常是 [1, num_boxes, 4+num_classes] 或 [1, num_classes, num_boxes]
    // 對於 YOLOv8n，輸出通常是 [1, 84, 8400] (84 是 4 框座標 + 80 類別分數)
    // 我們有兩個類別 (球, 桿頭)，所以輸出可能有所不同
    final outputBuffer = List.filled(_outputShape[0][0] * _outputShape[0][1] * _outputShape[0][2], 0.0).reshape(_outputShape[0]);

    // 執行推論
    try {
      _interpreter.run(inputBuffer.buffer.asUint8List().buffer, outputBuffer.buffer);
    } catch (e) {
      print('推論執行失敗: $e');
      return null;
    }

    // TODO: 解析模型輸出，提取邊界框和信心度
    // 這部分邏輯將取決於 YOLOv8n TFLite 模型的確切輸出格式。
    // 通常需要進行 NMS (Non-Maximum Suppression) 和閾值處理。
    final List<BoundingBox> detectedObjects = [];

    // 假設輸出格式為 [1, num_detections, 6] (x1, y1, x2, y2, confidence, class_id)
    // 或者 [1, 84, 8400] 這種需要後處理的格式
    // 這裡僅為示意，需要根據實際模型輸出調整解析邏輯
    final outputData = outputBuffer as List<List<List<double>>>; // 假設是這種結構

    // 假設 outputData[0] 包含所有檢測結果
    // 並且每個檢測結果是 [x_center, y_center, width, height, confidence, class_id_0_score, class_id_1_score, ...]
    // 或者直接是 [x1, y1, x2, y2, confidence, class_id]
    const double confidenceThreshold = 0.25; // 信心度閾值

    // 這是 YOLOv8n 的典型輸出解析方式，需要根據實際模型調整
    // 假設 outputData[0] 是 [num_classes + 4, num_boxes]
    // 或 [1, num_boxes, num_classes + 4]
    // 這裡假設輸出是 [1, num_detections, 6] -> [x1, y1, x2, y2, confidence, class_id]
    // 假設 outputData 是一個 List<List<double>>，其中每個內部 List 是一個檢測結果
    // 並且假設 class_id 0 是球，1 是桿頭
    // 實際的 YOLOv8n TFLite 模型輸出可能需要更複雜的解析，例如從 [1, 84, 8400] 轉換

    // TODO: 根據實際模型輸出結構，實現正確的邊界框解析和 NMS
    // 以下為示意性代碼，需要根據實際模型輸出調整
    // 假設輸出是 [1, 8400, 6] (x, y, w, h, conf, class_id)
    // 或者 [1, 84, 8400] (box_coords, class_scores)
    // 這裡假設 outputBuffer 已經被正確解析為一個包含檢測結果的列表
    // 每個結果包含 [x1, y1, x2, y2, confidence, class_id]
    // 假設輸出是 List<List<double>> 結構，每個子列表代表一個檢測結果

    // 由於 YOLOv8n 的 TFLite 輸出格式多樣，這裡提供一個通用但需調整的解析骨架
    // 通常，輸出會是一個扁平化的 Float32List，需要手動重塑和解析
    // 假設 outputBuffer 是一個 Float32List，代表所有的檢測結果
    final Float32List rawOutput = outputBuffer.cast<Float32List>(); // 假設輸出是扁平化的

    // 這裡需要知道模型的輸出維度，例如 [1, num_detections, 6]
    // 假設 num_detections 是 8400，每個檢測結果有 6 個值 (x1, y1, x2, y2, conf, class_id)
    final int numDetections = _outputShape[0][1]; // 假設是第二個維度
    final int valuesPerDetection = _outputShape[0][2]; // 假設是第三個維度

    // 遍歷所有潛在的檢測結果
    for (int i = 0; i < numDetections; i++) {
      final double confidence = rawOutput[i * valuesPerDetection + 4]; // 假設信心度在第5個位置
      if (confidence > confidenceThreshold) {
        final double x1 = rawOutput[i * valuesPerDetection + 0];
        final double y1 = rawOutput[i * valuesPerDetection + 1];
        final double x2 = rawOutput[i * valuesPerDetection + 2];
        final double y2 = rawOutput[i * valuesPerDetection + 3];
        final int classId = rawOutput[i * valuesPerDetection + 5].toInt(); // 假設類別 ID 在第6個位置

        // 將邊界框座標從模型輸入尺寸縮放回原始圖像尺寸
        final double scaleX = width / inputWidth;
        final double scaleY = height / inputHeight;

        detectedObjects.add(BoundingBox(
          x: x1 * scaleX,
          y: y1 * scaleY,
          width: (x2 - x1) * scaleX,
          height: (y2 - y1) * scaleY,
          confidence: confidence,
          className: classId == 0 ? 'ball' : 'club_head', // 假設 0 是球，1 是桿頭
        ));
      }
    }

    // TODO: 執行非極大值抑制 (NMS) 以消除重複的邊界框
    // 這是一個複雜的算法，通常需要額外的庫或手動實現。
    // 這裡暫時跳過 NMS，直接返回所有高信心度的框。
    // 實際應用中，NMS 對於準確的檢測至關重要。

    return detectedObjects;
  }

  void close() {
    _interpreter.close();
  }
}

// 邊界框數據模型
class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;
  final String className;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.className,
  });

  // 獲取中心點座標
  Offset get center => Offset(x + width / 2, y + height / 2);
}

lib/services/kalman.dart
// lib/services/kalman.dart
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart'; // 引入向量數學庫

/// 一維 Kalman Filter
class KalmanFilter1D {
  double _xHat; // 估計值
  double _p; // 估計誤差協方差
  final double _q; // 過程噪聲協方差
  final double _r; // 測量噪聲協方差

  KalmanFilter1D({
    required double initialEstimate,
    required double initialEstimateError,
    required double processNoise,
    required double measurementNoise,
  })  : _xHat = initialEstimate,
        _p = initialEstimateError,
        _q = processNoise,
        _r = measurementNoise;

  /// 更新濾波器
  /// [measurement] 當前測量值
  double update(double measurement) {
    // 預測階段
    _p = _p + _q; // 預測誤差協方差

    // 更新階段
    final double k = _p / (_p + _r); // Kalman 增益
    _xHat = _xHat + k * (measurement - _xHat); // 更新估計值
    _p = (1 - k) * _p; // 更新誤差協方差

    return _xHat;
  }
}

/// 二維 Kalman Filter (用於追蹤球的中心座標)
class KalmanFilter2D {
  Vector4 _xHat; // 狀態向量 [x, y, vx, vy]
  Matrix4 _p; // 估計誤差協方差矩陣
  final Matrix4 _q; // 過程噪聲協方差矩陣
  final Matrix4 _r; // 測量噪聲協方差矩陣
  final Matrix4 _f; // 狀態轉移矩陣
  final Matrix2x4 _h; // 測量矩陣

  KalmanFilter2D({
    required Offset initialPosition,
    required double initialVelocityX,
    required double initialVelocityY,
    required double dt, // 時間步長
    required double processNoisePos, // 位置過程噪聲
    required double processNoiseVel, // 速度過程噪聲
    required double measurementNoisePos, // 測量噪聲
  })  : _xHat = Vector4(initialPosition.dx, initialPosition.dy, initialVelocityX, initialVelocityY),
        _p = Matrix4.identity() * 1000.0, // 初始誤差協方差，較大值表示不確定性高
        _q = Matrix4.zero()
          ..setEntry(0, 0, processNoisePos)
          ..setEntry(1, 1, processNoisePos)
          ..setEntry(2, 2, processNoiseVel)
          ..setEntry(3, 3, processNoiseVel),
        _r = Matrix4.zero()
          ..setEntry(0, 0, measurementNoisePos)
          ..setEntry(1, 1, measurementNoisePos),
        _f = Matrix4.identity()
          ..setEntry(0, 2, dt) // x = x + vx * dt
          ..setEntry(1, 3, dt), // y = y + vy * dt
        _h = Matrix2x4.zero()
          ..setEntry(0, 0, 1.0) // 測量 x
          ..setEntry(1, 1, 1.0); // 測量 y

  /// 更新濾波器
  /// [measurement] 當前測量值 (x, y)
  Offset update(Offset measurement) {
    // 預測階段
    _xHat = _f * _xHat; // 預測狀態
    _p = _f * _p * _f.transpose() + _q; // 預測誤差協方差

    // 更新階段
    final Matrix2x4 hT = _h.transpose();
    final Matrix2x2 s = _h * _p * hT + _r; // 測量預測協方差
    final Matrix4 k = _p * hT * s.invert(); // Kalman 增益

    final Vector2 z = Vector2(measurement.dx, measurement.dy); // 測量向量
    final Vector2 y = z - (_h * _xHat).xy; // 測量殘差

    _xHat = _xHat + (k * y.x).toVector4(); // 更新估計狀態 (這裡簡化了向量加法，需要根據實際情況調整)
    _p = (Matrix4.identity() - k * _h) * _p; // 更新誤差協方差

    return Offset(_xHat.x, _xHat.y);
  }
}

lib/widgets/hud_overlay.dart
// lib/widgets/hud_overlay.dart
import 'package:flutter/material.dart';

class HUDOverlay extends StatelessWidget {
  final double ballSpeed; // 球速 (m/s)
  final double launchAngle; // 發射角 (度)
  final double estimatedCarryDistance; // 預估飛行距離 (m)

  const HUDOverlay({
    super.key,
    required this.ballSpeed,
    required this.launchAngle,
    required this.estimatedCarryDistance,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16.0,
      top: 16.0,
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8.0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatText('Ball Speed:', '${ballSpeed.toStringAsFixed(1)} m/s'),
            const SizedBox(height: 8.0),
            _buildStatText('Launch Angle:', '${launchAngle.toStringAsFixed(1)}°'),
            const SizedBox(height: 8.0),
            _buildStatText('Distance (carry est.):', '${estimatedCarryDistance.toStringAsFixed(1)} m'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatText(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16.0,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(width: 8.0),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// TODO: 如果需要，可以添加 CustomPainter 來繪製邊界框等
class BoundingBoxPainter extends CustomPainter {
  final List<Rect> boundingBoxes; // 邊界框列表
  final Size previewSize; // 預覽畫面的實際尺寸
  final Size imageSize; // 圖像幀的原始尺寸

  BoundingBoxPainter({required this.boundingBoxes, required this.previewSize, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 計算縮放比例
    final double scaleX = previewSize.width / imageSize.width;
    final double scaleY = previewSize.height / imageSize.height;

    for (var box in boundingBoxes) {
      // 將邊界框從圖像幀尺寸縮放到預覽畫面尺寸
      final scaledRect = Rect.fromLTWH(
        box.left * scaleX,
        box.top * scaleY,
        box.width * scaleX,
        box.height * scaleY,
      );
      canvas.drawRect(scaledRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // 每次更新都重繪
  }
}

lib/screens/practice_screen.dart
// lib/screens/practice_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:golf_tracker/services/kalman.dart';
import 'package:golf_tracker/services/tflite_service.dart';
import 'package:golf_tracker/widgets/hud_overlay.dart';
import 'package:golf_tracker/services/database_service.dart'; // 引入數據庫服務

// 定義一個用於 Isolate 間通信的數據模型
class InferenceData {
  final Uint8List yuvBytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int uvBytesPerRow;

  InferenceData({
    required this.yuvBytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.uvBytesPerRow,
  });
}

// Isolate 入口函數
void inferenceIsolate(SendPort sendPort) async {
  final TFLiteService tfliteService = TFLiteService();
  await tfliteService.loadModel();

  // 初始化 Kalman Filter
  // 這裡的參數需要根據實際測試調整
  final KalmanFilter2D kalmanFilter = KalmanFilter2D(
    initialPosition: Offset.zero,
    initialVelocityX: 0.0,
    initialVelocityY: 0.0,
    dt: 1.0 / 240.0, // 240 fps
    processNoisePos: 0.1,
    processNoiseVel: 0.01,
    measurementNoisePos: 1.0,
  );

  // 用於計算初速的球心座標歷史
  final List<Offset> ballCenterHistory = [];
  const int historyLength = 5; // 儲存最近的 5 幀數據

  ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort); // 將 Isolate 的發送端口發回主 Isolate

  await for (var message in receivePort) {
    if (message is InferenceData) {
      final List<BoundingBox>? detections = tfliteService.runInference(
        message.yuvBytes,
        message.width,
        message.height,
      );

      Offset? ballCenter;
      Offset? clubHeadCenter;

      if (detections != null) {
        for (var box in detections) {
          if (box.className == 'ball') {
            ballCenter = box.center;
          } else if (box.className == 'club_head') {
            clubHeadCenter = box.center;
          }
        }
      }

      // 平滑球心座標
      if (ballCenter != null) {
        final Offset smoothedBallCenter = kalmanFilter.update(ballCenter);
        ballCenterHistory.add(smoothedBallCenter);
        if (ballCenterHistory.length > historyLength) {
          ballCenterHistory.removeAt(0);
        }
      }

      // TODO: 實時計算邏輯
      double ballSpeed = 0.0;
      double launchAngle = 0.0;
      double estimatedCarryDistance = 0.0;

      // 計算初速和發射角
      if (ballCenterHistory.length >= 3) { // 至少有 3 幀數據來計算
        // 檢測擊球瞬間
        // TODO: 實現擊球瞬間檢測邏輯 (例如，桿頭與球的距離突然變小，然後球開始加速)
        bool isImpact = false; // 假設檢測到擊球

        if (isImpact) {
          // 取擊球瞬間後 3 幀球心移動量 / Δt，計算初速
          // 假設 ballCenterHistory 的最後三幀是擊球後的數據
          final Offset p0 = ballCenterHistory[ballCenterHistory.length - 3];
          final Offset p1 = ballCenterHistory[ballCenterHistory.length - 2];
          final Offset p2 = ballCenterHistory[ballCenterHistory.length - 1];

          // 計算兩幀間的位移
          final Offset displacement1 = p1 - p0;
          final Offset displacement2 = p2 - p1;

          // 計算平均速度向量
          final double dt = 1.0 / 240.0; // 時間步長
          final Offset avgVelocity = (displacement1 + displacement2) / (2 * dt); // 平均速度向量

          ballSpeed = avgVelocity.distance; // 初速大小

          // 估算發射角 (球心線段對水平角度)
          launchAngle = atan2(-avgVelocity.dy, avgVelocity.dx) * 180 / pi; // 注意 y 軸方向，Flutter 座標系 y 軸向下

          // TODO: 簡化彈道預測公式
          // 這裡是一個非常簡化的拋體運動公式，不考慮空氣阻力、自旋等
          // 實際應用需要更複雜的彈道模型
          const double g = 9.81; // 重力加速度
          final double initialVelocityX = ballSpeed * cos(launchAngle * pi / 180);
          final double initialVelocityY = ballSpeed * sin(launchAngle * pi / 180);

          // 飛行時間 (假設落地點與擊球點高度相同)
          final double timeOfFlight = (2 * initialVelocityY) / g;
          estimatedCarryDistance = initialVelocityX * timeOfFlight;

          // 將數據存入數據庫
          await DatabaseService.instance.insertShot({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'speed': ballSpeed,
            'angle': launchAngle,
            'carry': estimatedCarryDistance,
          });
        }
      }

      sendPort.send({
        'detections': detections?.map((box) => {
          'x': box.x,
          'y': box.y,
          'width': box.width,
          'height': box.height,
          'confidence': box.confidence,
          'className': box.className,
        }).toList(),
        'ballSpeed': ballSpeed,
        'launchAngle': launchAngle,
        'estimatedCarryDistance': estimatedCarryDistance,
      });
    }
  }
}

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  StreamSubscription? _cameraStreamSubscription;
  final EventChannel _cameraStreamChannel = const EventChannel('com.example.golf_tracker/camera_stream');
  final MethodChannel _cameraControlChannel = const MethodChannel('com.example.golf_tracker/camera_control');

  List<BoundingBox> _boundingBoxes = [];
  double _ballSpeed = 0.0;
  double _launchAngle = 0.0;
  double _estimatedCarryDistance = 0.0;

  FlutterIsolate? _inferenceIsolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _startInferenceIsolate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraStreamSubscription?.cancel();
    _cameraController?.dispose();
    _inferenceIsolate?.kill();
    _receivePort?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changes are not handled here for camera.
    // CameraX and AVCaptureDevice handle their own lifecycle.
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => throw Exception('找不到後置相機'),
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.high, // 這裡設置為 high，實際幀率由原生代碼控制
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      // 啟動原生相機流
      _cameraStreamSubscription = _cameraStreamChannel.receiveBroadcastStream().listen((dynamic event) {
        if (event is Map) {
          final Uint8List yuvBytes = event['buffer'];
          final int width = event['width'];
          final int height = event['height'];
          final int bytesPerRow = event['bytesPerRow'];
          final int uvBytesPerRow = event['uvBytesPerRow'];

          // 將圖像數據發送到 Isolate 進行推論
          _sendPort?.send(InferenceData(
            yuvBytes: yuvBytes,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            uvBytesPerRow: uvBytesPerRow,
          ));
        }
      }, onError: (error) {
        print('相機流錯誤: $error');
      });

    } on CameraException catch (e) {
      print('初始化相機錯誤: $e');
    }
  }

  Future<void> _startInferenceIsolate() async {
    _receivePort = ReceivePort();
    _inferenceIsolate = await FlutterIsolate.spawn(inferenceIsolate, _receivePort!.sendPort);

    _receivePort!.listen((dynamic message) {
      if (message is SendPort) {
        _sendPort = message; // 接收 Isolate 的發送端口
      } else if (message is Map) {
        setState(() {
          if (message['detections'] != null) {
            _boundingBoxes = (message['detections'] as List).map((boxMap) => BoundingBox(
              x: boxMap['x'],
              y: boxMap['y'],
              width: boxMap['width'],
              height: boxMap['height'],
              confidence: boxMap['confidence'],
              className: boxMap['className'],
            )).toList();
          }
          _ballSpeed = message['ballSpeed'] ?? 0.0;
          _launchAngle = message['launchAngle'] ?? 0.0;
          _estimatedCarryDistance = message['estimatedCarryDistance'] ?? 0.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // 計算預覽畫面尺寸以適應屏幕
    final Size mediaSize = MediaQuery.of(context).size;
    final double aspectRatio = _cameraController!.value.aspectRatio;
    double previewWidth = mediaSize.width;
    double previewHeight = previewWidth / aspectRatio;

    if (previewHeight > mediaSize.height) {
      previewHeight = mediaSize.height;
      previewWidth = previewHeight * aspectRatio;
    }

    return Stack(
      children: [
        // 相機預覽畫面
        Center(
          child: SizedBox(
            width: previewWidth,
            height: previewHeight,
            child: CameraPreview(_cameraController!),
          ),
        ),
        // HUD 疊圖
        HUDOverlay(
          ballSpeed: _ballSpeed,
          launchAngle: _launchAngle,
          estimatedCarryDistance: _estimatedCarryDistance,
        ),
        // 邊界框疊圖
        Positioned.fill(
          child: CustomPaint(
            painter: BoundingBoxPainter(
              boundingBoxes: _boundingBoxes,
              previewSize: Size(previewWidth, previewHeight),
              imageSize: _cameraController!.value.previewSize!, // 相機預覽的原始尺寸
            ),
          ),
        ),
      ],
    );
  }
}

lib/services/database_service.dart
// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('shots.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE shots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp INTEGER NOT NULL,
  speed REAL NOT NULL,
  angle REAL NOT NULL,
  carry REAL NOT NULL
)
''');
  }

  // 插入一條擊球數據
  Future<int> insertShot(Map<String, dynamic> shot) async {
    final db = await instance.database;
    return await db.insert('shots', shot, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 獲取所有擊球數據
  Future<List<Map<String, dynamic>>> getAllShots() async {
    final db = await instance.database;
    final orderBy = 'timestamp DESC'; // 按時間降序排列
    return await db.query('shots', orderBy: orderBy);
  }

  // 關閉數據庫
  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}

scripts/convert_yolov8_to_tflite.py
# scripts/convert_yolov8_to_tflite.py
import torch
import onnx
import tensorflow as tf
from tensorflow.lite.python import lite_v2 as tflite
import os

# TODO: 確保已安裝 Ultralytics, onnx, tensorflow
# pip install ultralytics onnx tensorflow tensorflow-gpu

def convert_yolov8_to_tflite(model_path, output_dir=".", model_name="golfclub_ball_yolov8n"):
    """
    將 YOLOv8 模型 (PyTorch .pt) 轉換為 ONNX，然後再轉換為 TFLite 格式，
    並啟用 GPU delegate (如果可用)。

    Args:
        model_path (str): YOLOv8 PyTorch 模型 (.pt) 的路徑。
        output_dir (str): 輸出文件的目錄。
        model_name (str): 輸出 TFLite 模型的文件名 (不含擴展名)。
    """
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    onnx_path = os.path.join(output_dir, f"{model_name}.onnx")
    tflite_path = os.path.join(output_dir, f"{model_name}.tflite")

    print(f"載入 YOLOv8 模型: {model_path}")
    # TODO: 這裡需要根據實際的 YOLOv8 載入方式調整
    # 如果是 Ultralytics 的 YOLOv8，可以使用以下方式
    # from ultralytics import YOLO
    # model = YOLO(model_path)
    # 這裡我們假設 model_path 是一個 PyTorch .pt 文件，並且可以直接載入
    try:
        model = torch.load(model_path)['model'].float()
        model.eval()
        print("PyTorch 模型載入成功。")
    except Exception as e:
        print(f"載入 PyTorch 模型失敗，請確保這是有效的 YOLOv8 .pt 文件或調整載入方式: {e}")
        return

    # 1. 轉換為 ONNX
    print(f"開始轉換為 ONNX: {onnx_path}")
    dummy_input = torch.randn(1, 3, 640, 640) # YOLOv8n 預設輸入尺寸
    torch.onnx.export(
        model,
        dummy_input,
        onnx_path,
        verbose=True,
        opset_version=11, # 建議使用 11 或更高版本
        input_names=['images'],
        output_names=['output'],
        dynamic_axes={'images': {0: 'batch'}, 'output': {0: 'batch'}}
    )
    print("ONNX 轉換完成。")

    # 驗證 ONNX 模型
    try:
        onnx_model = onnx.load(onnx_path)
        onnx.checker.check_model(onnx_model)
        print("ONNX 模型驗證成功。")
    except Exception as e:
        print(f"ONNX 模型驗證失敗: {e}")
        return

    # 2. 轉換為 TFLite
    print(f"開始轉換為 TFLite: {tflite_path}")
    converter = tf.lite.TFLiteConverter.from_onnx(onnx_path)

    # 啟用優化
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    # 設定輸入類型 (通常是 FLOAT32)
    converter.target_spec.supported_types = [tf.float32]

    # 啟用 GPU delegate (如果可用)
    # 確保您的 TensorFlow 版本支持 GPU delegate
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS # 如果模型包含選擇性 TensorFlow 操作
    ]
    # TODO: 如果需要更精確的 GPU delegate 配置，可以在這裡添加
    # 例如：converter.experimental_new_converter = True
    # converter.allow_custom_ops = True # 如果有自定義操作

    # 進行轉換
    tflite_model = converter.convert()

    # 保存 TFLite 模型
    with open(tflite_path, 'wb') as f:
        f.write(tflite_model)
    print("TFLite 轉換完成。")
    print(f"TFLite 模型已保存到: {tflite_path}")

if __name__ == "__main__":
    # 替換為您的 YOLOv8 .pt 模型路徑
    # TODO: 請將 'path/to/your/golfclub_ball_yolov8n.pt' 替換為您實際的模型文件路徑
    # 您需要先訓練或下載一個 YOLOv8n 模型，並確保其輸出符合您的需求（球和桿頭的邊界框）
    # 如果您只有 ONNX 模型，可以直接從 ONNX 轉換：
    # converter = tf.lite.TFLiteConverter.from_onnx(onnx_path)
    # 並移除 PyTorch 到 ONNX 的步驟。
    yolov8_pt_model_path = 'path/to/your/golfclub_ball_yolov8n.pt'
    output_directory = '../assets/models' # 輸出到 assets/models 資料夾

    # 檢查模型文件是否存在
    if not os.path.exists(yolov8_pt_model_path):
        print(f"錯誤: 找不到模型文件 '{yolov8_pt_model_path}'。請提供正確的路徑。")
        print("您可以從 Ultralytics 下載預訓練的 YOLOv8n 模型，然後訓練它來識別高爾夫球和桿頭。")
        print("或者，如果您已經有 ONNX 格式的模型，可以直接從 ONNX 轉換。")
    else:
        convert_yolov8_to_tflite(yolov8_pt_model_path, output_dir=output_directory)