# Testing and going live

[← Kinetikos Tracker SDK for iOS](../README.md)

## Testing

- **Use a real iPhone.** The simulator has no motion recorder, so background recording can't be tested there.
- Point the SDK at `.development` or `.staging`, with a test tenant and that environment's credentials from Kinetikos.
- Background work isn't immediate: iOS decides when background tasks run. Open the app to trigger an upload, or call `syncNow()`.
- Walk to test passive recording: walking periods are detected by iOS and collected later, not live.

## App Store review: the `audio` background mode

The SDK plays **silent audio** while a recorded walk or a walk test is running, so the recording continues while the screen is locked. Background tracking doesn't use it. Reviewers may ask why an app that plays no sound declares `audio`. In **App Review Information → Notes**, explain:

> *"The app records a timed walking test (6 minutes) using the motion sensors. To keep recording while the phone is locked in the user's pocket, the embedded Kinetikos SDK plays silent audio only while a test is running. No audio is played or recorded otherwise."*

## Privacy

The SDK ships a privacy manifest (`PrivacyInfo.xcprivacy`). Xcode merges it into your app's privacy report. It declares motion (fitness) data and device model / OS version, linked to the participant and never used for tracking.

## Before you release

- [ ] Server: client credentials kept server-side; invite; participant-token endpoint for your app; revoke ([Your backend](backend.md)).
- [ ] Package added; `import TrackerSDK`.
- [ ] Info.plist: `NSMotionUsageDescription`, four `UIBackgroundModes`, three `BGTaskSchedulerPermittedIdentifiers`.
- [ ] Capabilities: Push Notifications, Background Modes.
- [ ] App delegate: `configure`, `registerBackgroundTasks`, push token, remote notification, background session.
- [ ] `tokenProvider` works in the background without UI; returns `nil` when signed out.
- [ ] Consent screen with `consentDocument` and `giveConsent`; withdrawal in settings.
- [ ] `requestPermissions`, then `startTracking` on every launch while signed in.
- [ ] `signOut()` before your own sign-out.
- [ ] App Review note about the `audio` background mode.
- [ ] `.production` in `Tracker.configure`, with your production credentials on your server.
- [ ] Tested on a real iPhone against development or staging.
