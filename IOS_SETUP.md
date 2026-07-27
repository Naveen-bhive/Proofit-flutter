# ProofIt — iOS Setup Guide
Complete checklist to get ProofIt running on iOS / App Store.

---

## 1. Minimum Requirements
- Mac with Xcode 15+ installed
- Apple Developer Account ($99/year) for App Store
- iOS 14.0+ target (required by Google Maps Flutter)
- CocoaPods installed: `sudo gem install cocoapods`

---

## 2. Open Project in Xcode

```bash
cd proofit/flutter_app
flutter pub get
cd ios && pod install
open Runner.xcworkspace   # Always open .xcworkspace NOT .xcodeproj
```

---

## 3. Bundle Identifier & Signing

In Xcode:
- Select **Runner** in the left panel
- **General** tab:
  - Bundle Identifier: `com.bhive.proofit`
  - Version: `1.0.0`
  - Build: `1`
- **Signing & Capabilities** tab:
  - Team: Select your Apple Developer team
  - Automatically manage signing: ✅ ON
  - Xcode will auto-generate provisioning profile

---

## 4. Google Maps API Key

In `ios/Runner/AppDelegate.swift`:
```swift
GMSServices.provideAPIKey("YOUR_ACTUAL_GOOGLE_MAPS_API_KEY")
```

In Google Cloud Console:
- Restrict key to iOS apps
- Add bundle ID: `com.bhive.proofit`

---

## 5. Firebase Setup (FCM Push Notifications)

```
1. Firebase Console → Add iOS app
   Bundle ID: com.bhive.proofit
   App nickname: ProofIt iOS

2. Download GoogleService-Info.plist

3. In Xcode:
   Right-click Runner folder → Add Files to "Runner"
   Select GoogleService-Info.plist
   ✅ Check "Copy items if needed"
   ✅ Check "Add to targets: Runner"

4. Enable Push Notifications capability in Xcode:
   Signing & Capabilities → + Capability → Push Notifications

5. Enable Background Modes:
   Signing & Capabilities → + Capability → Background Modes
   ✅ Background fetch
   ✅ Remote notifications
```

---

## 6. Associated Domains (Deep Links / Invite URLs)

```
Xcode → Signing & Capabilities → + Capability → Associated Domains
Add: applinks:app.proofitapp.in
```

Also add to your domain server (Hostinger):
Create file at: `https://app.proofitapp.in/.well-known/apple-app-site-association`

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "YOUR_TEAM_ID.com.bhive.proofit",
        "paths": ["/invite/*"]
      }
    ]
  }
}
```

Replace `YOUR_TEAM_ID` with your Apple Developer Team ID (found in developer.apple.com).

---

## 7. Razorpay iOS Setup

Razorpay requires additional iOS config.

In `ios/Runner/Info.plist` — already added:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>proofit</string></array>
  </dict>
</array>
```

In `AppDelegate.swift` — already handles `open url` callback.

Razorpay also needs in Podfile (already set):
```ruby
platform :ios, '14.0'
use_frameworks!
```

---

## 8. Camera & Location — Runtime Permission

Already in `Info.plist`:
- `NSCameraUsageDescription` ✅
- `NSLocationWhenInUseUsageDescription` ✅
- `NSLocationAlwaysAndWhenInUseUsageDescription` ✅
- `NSPhotoLibraryUsageDescription` ✅
- `NSMicrophoneUsageDescription` ✅

The app requests these at runtime via `permission_handler` package.

---

## 9. App Icons

```bash
# 1. Place 1024x1024px icon.png in assets/images/
# 2. Run generator:
flutter pub run flutter_launcher_icons

# This creates all required iOS icon sizes in:
# ios/Runner/Assets.xcassets/AppIcon.appiconset/
```

iOS requires these specific sizes (auto-generated):
- 20pt, 29pt, 40pt, 60pt, 76pt, 83.5pt, 1024pt

---

## 10. Splash Screen

```bash
flutter pub run flutter_native_splash:create
```

This creates the LaunchScreen.storyboard with your splash image.

---

## 11. Build & Test

```bash
# Run on iOS Simulator
flutter run -d "iPhone 15"

# Run on physical device (requires Apple Developer account)
flutter run -d [device-udid]

# Build for App Store
flutter build ipa --release

# Output: build/ios/ipa/proofit.ipa
```

---

## 12. App Store Submission Checklist

Before submitting to App Store Connect:

| Item | Status |
|---|---|
| Bundle ID registered in developer.apple.com | ⬜ |
| App Store Connect app record created | ⬜ |
| Screenshots (6.7", 6.1", 5.5" required) | ⬜ |
| App description + keywords | ⬜ |
| Privacy policy URL | ⬜ |
| Support URL | ⬜ |
| Age rating completed | ⬜ |
| Export compliance (No encryption beyond HTTPS) | ⬜ |
| TestFlight beta tested | ⬜ |

---

## 13. Common iOS Errors & Fixes

| Error | Fix |
|---|---|
| `pod install` fails | Run `sudo gem install cocoapods` then retry |
| `Module not found` | Run `flutter pub get` then `pod install` again |
| `Signing certificate not found` | Sign in to Xcode with Apple ID → Preferences → Accounts |
| Camera not working on simulator | Use physical device — simulator has no camera |
| Maps not showing | Check API key in AppDelegate.swift |
| Push not working | Check GoogleService-Info.plist is added to Xcode target |
| Build fails with `arm64` error | Already fixed in Podfile — `EXCLUDED_ARCHS[sdk=iphonesimulator*]` |
| Razorpay payment sheet crashes | Ensure `use_frameworks!` is in Podfile ✅ |

---

## Package iOS Compatibility

| Package | iOS Min | Notes |
|---|---|---|
| `razorpay_flutter` | iOS 10+ | ✅ Supported |
| `google_maps_flutter` | iOS 14+ | ✅ Works fine |
| `geolocator` | iOS 10+ | ✅ Supported |
| `camera` | iOS 10+ | ✅ Supported |
| `firebase_messaging` | iOS 10+ | ✅ Supported |
| `flutter_local_notifications` | iOS 10+ | ✅ Supported |
| `go_router` | iOS 12+ | ✅ Supported |
| `flutter_secure_storage` | iOS 9+ | ✅ Supported |
| `connectivity_plus` | iOS 12+ | ✅ Supported |

All packages support iOS 13+ — our minimum target. ✅