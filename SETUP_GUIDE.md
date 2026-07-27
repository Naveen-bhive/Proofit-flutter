# ProofIt Flutter — Setup Guide

## Step 1: Google Maps API Key

### Get API Key
1. Go to https://console.cloud.google.com
2. Create a project → Enable "Maps SDK for Android" + "Maps SDK for iOS"
3. APIs & Services → Credentials → Create API Key
4. Restrict key to your app package name for security

### Android — AndroidManifest.xml
File: `android/app/src/main/AndroidManifest.xml`
Add inside `<application>` tag:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_MAPS_API_KEY"/>
```

### iOS — AppDelegate.swift
File: `ios/Runner/AppDelegate.swift`
```swift
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

---

## Step 2: Firebase Setup (FCM Push Notifications)

1. Go to https://console.firebase.google.com
2. Create project → Add Android app (package: `com.bhive.proofit`)
3. Download `google-services.json` → place in `android/app/`
4. Add iOS app → Download `GoogleService-Info.plist` → place in `ios/Runner/`

### android/build.gradle
```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.0'
}
```

### android/app/build.gradle
```gradle
apply plugin: 'com.google.gms.google-services'
```

---

## Step 3: Deep Link Setup (Invite Links)

### Android — AndroidManifest.xml
Add inside `<activity>` tag:
```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https" android:host="app.proofitapp.in"/>
</intent-filter>
```

### iOS — Info.plist
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array><string>proofit</string></array>
    </dict>
</array>
```

### iOS — Associated Domains (Xcode)
- Signing & Capabilities → + → Associated Domains
- Add: `applinks:app.proofitapp.in`

---

## Step 4: iOS Permissions — Info.plist

File: `ios/Runner/Info.plist`
Add these permission strings (required for App Store):
```xml
<key>NSCameraUsageDescription</key>
<string>ProofIt needs camera access to capture before and after photos of your work.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>ProofIt stamps your GPS location on each report to verify where work was done.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>ProofIt uses your location to verify work locations and enable live tracking for your team.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>ProofIt needs photo library access to attach images to your reports.</string>

<key>NSMicrophoneUsageDescription</key>
<string>ProofIt needs microphone access for video reports.</string>

<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

---

## Step 5: Android Permissions — AndroidManifest.xml

Add inside `<manifest>` tag:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-feature android:name="android.hardware.camera" android:required="true"/>
```

---

## Step 6: App Package Name

Change package name from default to `com.bhive.proofit`:

### Android
File: `android/app/build.gradle`
```gradle
defaultConfig {
    applicationId "com.bhive.proofit"
    minSdkVersion 21
    targetSdkVersion 34
    ...
}
```

### iOS — Xcode
- Open `ios/Runner.xcworkspace` in Xcode
- Runner → General → Bundle Identifier: `com.bhive.proofit`

---

## Step 7: Update API Base URL

File: `lib/core/constants/app_constants.dart`
```dart
static const String baseUrl = 'https://api.proofitapp.in/api';
```

---

## Quick Start

```bash
# 1. Install dependencies
flutter pub get

# 2. Check setup
flutter doctor

# 3. Run on Android
flutter run -d android

# 4. Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# 5. Build App Bundle (for Play Store)
flutter build appbundle --release
```