# SmartPOC - Ambient AI Multimodal Wearable Platform

SmartPOC is a multimodal ambient AI platform designed for smart wearable glasses (such as Meta Ray-Ban Smart Glasses) and mobile camera vision systems. It integrates real-time computer vision, gaze grounding, neural audio VAD, speaker biometrics, psychological behaviour intent gating, and context-primed e-commerce recommendations.

---

## 📋 Table of Contents
1. [Prerequisites & System Requirements](#-prerequisites--system-requirements)
2. [Step-by-Step Installation & Setup](#-step-by-step-installation--setup)
3. [Environment Configuration (.env)](#-environment-configuration-env)
4. [Running the Application](#-running-the-application)
   - [Android (Physical Device & Emulator)](#1-android-physical-device--emulator)
   - [Meta Ray-Ban Smart Glasses & USB-C Cameras](#2-meta-ray-ban-smart-glasses--usb-c-cameras)
   - [iOS (Device & Simulator)](#3-ios-device--simulator)
   - [Web (Development Mode & CORS Proxy)](#4-web-development-mode--cors-proxy)
5. [Building Production Releases](#-building-production-releases)
6. [Testing & Quality Verification](#-testing--quality-verification)
7. [Developer Tools & Helper Scripts](#-developer-tools--helper-scripts)
8. [Troubleshooting & Common Issues](#-troubleshooting--common-issues)
9. [Documentation Sitemap](#-documentation-sitemap)

---

## 🛠️ Prerequisites & System Requirements

Before setting up SmartPOC on your device, ensure you have installed the following developer tools:

| Component | Minimum Version | Recommended / Details |
| :--- | :--- | :--- |
| **Flutter SDK** | `>= 3.5.0` | [Install Flutter](https://docs.flutter.dev/get-started/install) |
| **Dart SDK** | `>= 3.5.0` | Bundled with Flutter SDK |
| **Android Studio** | Hedgehog (2023.1.1+) | Includes Android SDK Build-Tools & NDK |
| **Android OS** | Android 10+ (API Level 29+) | ARM64-v8a architecture for ONNX runtime |
| **Xcode** *(macOS only)* | Version 15.0+ | Required for iOS builds & simulators |
| **Node.js** *(Optional)* | v18.0+ | Required for running the local web CORS proxy |

---

## 🚀 Step-by-Step Installation & Setup

### 1. Clone the Repository
Clone the codebase to your local machine:
```bash
git clone https://github.com/GlassData-GD/Ecom-Companion-App.git
cd Ecom-Companion-App
```

### 2. Configure Environment Variables
Copy `.env.example` to create your local `.env` configuration file:
```bash
# On Linux / macOS / Git Bash:
cp .env.example .env

# On Windows PowerShell:
Copy-Item .env.example .env
```

### 3. Install Flutter Dependencies
Run `flutter pub get` to download and link all required Dart packages and ONNX model assets:
```bash
flutter pub get
```

---

## ⚙️ Environment Configuration (.env)

The application uses `flutter_dotenv` to manage configuration variables. Simply copy `.env.example` to `.env` in the root directory:

```bash
# On Linux / macOS / Git Bash:
cp .env.example .env

# On Windows PowerShell:
Copy-Item .env.example .env
```

Refer to `.env.example` for the required keys and default template values.

---

## 📱 Running the Application

### 1. Android (Physical Device & Emulator)

#### Physical Android Device (Recommended)
1. Enable **Developer Options** and **USB Debugging** on your phone (*Settings > About Phone > Tap 'Build Number' 7 times*).
2. Connect your Android device via USB.
3. Verify the device is recognized:
   ```bash
   flutter devices
   ```
4. Run the app:
   ```bash
   flutter run
   ```
5. When prompted on your phone, accept runtime permissions for **Camera**, **Microphone**, and **Location**.

#### Android Emulator
1. Open Android Studio Device Manager and launch an ARM64 or x86_64 Virtual Device (Android 10+ / API 29+).
2. Run:
   ```bash
   flutter run
   ```

---

### 2. Meta Ray-Ban Smart Glasses & USB-C Cameras
SmartPOC supports POV camera feeds from Meta Ray-Ban Smart Glasses or external USB-C cameras connected via OTG:
1. Launch the app and navigate to the **Choose Input Source** screen (`/choose-source`).
2. Select **Meta Glasses / External Camera**.
3. Grant USB/UVC camera access when prompted by Android.

---

### 3. iOS (Device & Simulator) *(macOS only)*
1. Navigate to the `ios` directory and install CocoaPods dependencies:
   ```bash
   cd ios
   pod install
   cd ..
   ```
2. Launch an iOS Simulator or connect an iPhone:
   ```bash
   flutter run -d iphonesimulator
   # OR for physical iPhone:
   flutter run -d <device_id>
   ```

---

### 4. Web (Development Mode & CORS Proxy)
Browser security blocks direct cross-origin API calls to `https://myna.glassdata.ai`. To test the web build locally:

1. **Start the local CORS Proxy**:
   ```bash
   node scripts/cors_proxy.js 5050
   ```
2. Point `ECOM_HUB_*` URLs in `.env` to `http://localhost:5050/api/v1/ah/...`.
3. **Launch Chrome in Flutter**:
   ```bash
   flutter run -d chrome
   ```

---

## 📦 Building Production Releases

### Build Android APK
Generate an optimized release APK:
```bash
flutter build apk --release
```
Output location: `build/app/outputs/flutter-apk/app-release.apk`

### Build Android App Bundle (AAB for Google Play)
```bash
flutter build appbundle --release
```
Output location: `build/app/outputs/bundle/release/app-release.aab`

### Build Web Package
```bash
flutter build web --release
```
Output location: `build/web/`

---

## 🧪 Testing & Quality Verification

SmartPOC includes automated unit tests, widget tests, and static code verification.

### Run Unit & Widget Tests
Execute the full test suite:
```bash
flutter test
```

### Run Static Code Analysis
Run Dart analyzer across all application packages, tests, and CLI scripts:
```bash
dart analyze lib test bin
```

---

## 🛠️ Developer Tools & Helper Scripts

- **Inspect Postgres Saved Items**:
  Inspect saved database items from the command line:
  ```bash
  dart bin/inspect_saved_items.dart
  ```

- **Verify Owned Objects Endpoint**:
  Test GET/POST/DELETE operations against the Behaviour Engine owned objects API:
  ```bash
  dart bin/test_be_owned_objects.dart
  ```

- **No-Cache Web Server**:
  Serve the release web build locally without browser caching:
  ```bash
  node scripts/serve_web_no_cache.mjs
  ```

---

## ❓ Troubleshooting & Common Issues

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **`MissingPluginException` in tests** | Mock services require binding initialization | Run tests using `flutter test` which automatically initializes Flutter test bindings. |
| **CORS errors on Web** | Browsers block direct `myna.glassdata.ai` requests | Run `node scripts/cors_proxy.js 5050` and point `.env` URLs to localhost. |
| **PostgreSQL SSL Error** | RDS database connection requires SSL mode | Ensure `sslMode: SslMode.require` is configured in `ConnectionSettings` or update `.env`. |
| **ONNX Model Load Error** | Missing ONNX assets in asset path | Run `flutter pub get` and verify files exist under `assets/models/`. |
| **Camera Permission Denied** | Runtime permission rejected | Open device settings > Apps > SmartPOC > Permissions > Enable Camera and Microphone. |

---

## 📚 Documentation Sitemap

- 📄 **System Architecture Specification**: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 📄 **Operational User Manual & Visual Guide**: [USER_GUIDE_MANUAL.md](USER_GUIDE_MANUAL.md)
- 📄 **Environment Sample**: [.env.example](.env.example)
