# golf-tracker

**手機前置或後置鏡頭高爾夫擊球追蹤應用程式**

## Quick Start

1. **Read CLAUDE.md first** - Contains essential rules for Claude Code
2. Follow the pre-task compliance checklist before starting any work
3. Use proper module structure under `src/main/dart/`
4. Commit after every completed task

## AI/ML Project Structure

This project uses a complete MLOps-ready structure with:

**Flutter Development:** Modern mobile app with native camera integration  
**Computer Vision:** TensorFlow Lite YOLOv8n for real-time object detection  
**Native Performance:** High-speed camera capture (240fps) with platform-specific optimization

## Features

- 📱 Flutter-based mobile application
- 📷 High-speed camera capture (240fps)
- 🤖 Real-time ball and club head detection
- 📊 Ball speed, launch angle, and distance calculation
- 💾 SQLite database for shot history
- 🔄 Kalman filtering for smooth tracking
- ⚡ Native iOS (Swift) and Android (Kotlin) integration

## Development Guidelines

- **Always search first** before creating new files
- **Extend existing** functionality rather than duplicating  
- **Use Task agents** for operations >30 seconds
- **Single source of truth** for all functionality
- **Language-agnostic structure** - supports Dart, Swift, Kotlin
- **Scalable** - start simple, grow as needed
- **AI/ML Ready** - includes MLOps directories for models and experiments

## Project Structure

```
golf-tracker/
├── src/main/dart/          # Flutter/Dart source code
├── src/main/swift/         # iOS native implementation
├── src/main/kotlin/        # Android native implementation
├── models/                # TensorFlow Lite models
├── data/                  # Dataset management
├── experiments/           # ML experiment tracking
├── notebooks/             # Analysis and prototyping
└── .claude/agents/        # Specialized development agents
```

## Getting Started

```bash
# Install Flutter dependencies
flutter pub get

# Run on device/emulator
flutter run

# Run tests
flutter test

# Analyze code
flutter analyze
```

## Sub-Agents Available

- `flutter-dart-dev` - Flutter/Dart development specialist
- `native-mobile-dev` - iOS/Android native development
- `computer-vision-ml` - TensorFlow Lite and computer vision
- `database-ops` - SQLite optimization and data management
- `perf-optimizer` - Performance analysis and optimization

---

**🎯 Template by Chang Ho Chien | HC AI 說人話channel | v1.0.0**  
📺 Tutorial: https://youtu.be/8Q1bRZaHH24