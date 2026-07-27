IMPORTANT: Place your GoogleService-Info.plist file here.

Steps:
1. Go to Firebase Console (https://console.firebase.google.com)
2. Select your ProofIt project
3. Project Settings → iOS App (com.bhive.proofit)
4. Download GoogleService-Info.plist
5. Place it in this folder: ios/Runner/GoogleService-Info.plist
6. In Xcode: right-click Runner folder → Add Files → select the plist
   IMPORTANT: Make sure "Copy items if needed" is checked

Without this file, FCM push notifications will NOT work on iOS.