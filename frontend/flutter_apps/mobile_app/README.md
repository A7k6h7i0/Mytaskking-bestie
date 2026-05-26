# MyTaskKing Mobile

## Firebase push notifications

The app registers the current device token with `/notifications/devices` after
login and shows foreground Firebase pushes with a local notification. Tapping a
push opens the matching chat, task, call, meeting, telecaller, or notification
screen.

Use one of these Firebase configuration paths:

1. Add native Firebase files:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`

2. Or pass mobile Firebase values with `--dart-define`:

```powershell
flutter run `
  --dart-define=FIREBASE_API_KEY=your_api_key `
  --dart-define=FIREBASE_PROJECT_ID=mytaskking `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=239833916361 `
  --dart-define=FIREBASE_STORAGE_BUCKET=mytaskking.firebasestorage.app `
  --dart-define=FIREBASE_ANDROID_APP_ID=your_android_app_id
```

For iOS, use `FIREBASE_IOS_APP_ID` and optionally
`FIREBASE_IOS_BUNDLE_ID=com.mytaskking.mobile`.
