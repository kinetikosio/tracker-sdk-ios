# Kinetikos Tracker SDK for iOS — Integration Guide

The SDK records a participant's walking in the background, uploads it to Kinetikos, and runs the 6-minute walk test, inside **your** app. Your users stay in your app and keep your login: the SDK never shows a Kinetikos sign-in, and has no UI of its own.

This guide takes you from an empty project to a working integration. Do the steps in order.

> **Status:** pre-release (spec v0.2). Two items are marked *Not available yet* below; everything else works today.

---

## 1. How it fits together

Two systems of yours talk to Kinetikos: your **backend** and your **app**.

```
Your backend ──(1) client credentials──► Kinetikos   invite / revoke participants
Your backend ──(2) "token for P-17"────► Kinetikos   returns a participant token
Your app ◄──── participant token ──────── your backend
Your app ──► SDK ──(3) data, with token─► Kinetikos   recordings, consent
```

1. **Your backend** holds the client credentials Kinetikos gave you. With them it invites the people who take part (by *your* id for them, the `external_id`), and revokes them when they stop.
2. When your app needs it, **your backend** asks Kinetikos for a **participant token** for one person and passes it to your app. The first token for an invited person also enrolls them.
3. **Your app** gives that token to the SDK, which sends the person's data with it.

**The client credentials never go in your app.** Anything in an app can be extracted. Your app only ever holds participant tokens, which last eight hours and work for one person.

### What you need from Kinetikos

- A **tenant** (your isolated space) and **client credentials** for your backend, with the `participants:write` and `participants:token` scopes.
- Which **environment** to use. Each is a separate Kinetikos backend, with its own tenant and client credentials, and a participant token works only on the backend that issued it: your backend and the SDK must use the same one.

  | Environment | Backend URL (`<host>` below) | In the SDK |
  |---|---|---|
  | Development | `https://tracker-api-dev.kinetikos.io` | `.development` |
  | Staging | `https://tracker-api-stg.kinetikos.io` | `.staging` |
  | Production | `https://tracker-api.kinetikos.io` | `.production` |
- The **SDK package** (see §3).

### What Kinetikos needs from you

- Your app's **bundle ID**.
- *(Not available yet: per-integrator silent pushes; see §5.4)* Your **APNs key** (`.p8`), its key ID, and your team ID.

---

## 2. Your backend

Your backend calls two Kinetikos endpoints. Full reference: the Kinetikos *Integration API* document.

### 2.1 Get your backend's token

```sh
curl -X POST https://<host>/v1/oauth/token \
  -u "$CLIENT_ID:$CLIENT_SECRET" \
  -d grant_type=client_credentials -d scope="participants:write participants:token"
```

Cache it until `expires_in` runs out.

### 2.2 Invite a participant

When someone in your system should be tracked (they joined a programme, a clinician enrolled them…):

```sh
curl -X POST https://<host>/v1/participants -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"external_id":"P-17"}'
```

Inviting the same `external_id` again is safe; it returns the existing invitation. Invite only the people who will actually be tracked.

### 2.3 Give your app participant tokens

Add an endpoint **on your backend** that your app calls with the user's own session (your login). It checks who the user is, then asks Kinetikos for that person's token:

```sh
curl -X POST https://<host>/v1/participant-tokens -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"external_id":"P-17"}'
```

```json
{ "access_token": "eyJhbGciOi...", "token_type": "Bearer", "expires_in": 28800, "participant": { "status": "enrolled", "…": "…" } }
```

- **Only hand a person's token to that person.** Kinetikos trusts your backend to say who is who.
- Tokens last `expires_in` seconds (8 hours). Cache each person's token and fetch a new one shortly before it expires, not on every call. Revoking someone or suspending your institution takes effect at once, whatever token their phone holds.
- `403 PARTICIPANT_REVOKED`: the person was revoked. Don't return a token; your app should stop asking for a while.
- `403 TENANT_INACTIVE`: your institution is suspended or has ended the study. Don't return a token (throw from `tokenProvider`); it works again as soon as the institution is active.
- `404 NOT_FOUND`: never invited. Invite them first, if they should take part.
- `409 ENROLLED_IN_APP`: the person enrolled in the Kinetikos app with their Enrollment Code. Participant tokens are only for people who use the SDK.
- `409 CONFLICT` (rare), `429 TOO_MANY_REQUESTS` (your institution's limit; wait for `Retry-After`) and `503 SERVICE_UNAVAILABLE`: retry later. Meanwhile return your cached token if it is still valid, or throw: the SDK keeps recording and uploads later.

### 2.4 Revoke

When someone should stop being tracked: `POST /v1/participants/{id}/revoke`. Their phone stops recording and deletes what it hadn't sent the next time it talks to Kinetikos. To bring them back, invite them again: they keep their history, but must give consent again in your app.

---

## 3. Add the SDK to your app

**Requirements:** iOS 17 or later. Xcode 26 or later (the SDK is built with Swift 6.2).

The SDK is a pre-built binary framework (`TrackerSDK.xcframework`) with no dependencies of its own. In Xcode choose **File → Add Package Dependencies…**, enter `https://github.com/kinetikosio/tracker-sdk-ios`, choose a version (e.g. *Up to Next Major* from `1.0.0`), and add the **TrackerSDK** library to your app target. Xcode downloads the framework and checks its checksum and signature.

```swift
import TrackerSDK
```

The SDK ships a privacy manifest (`PrivacyInfo.xcprivacy`). Xcode merges it into your app's privacy report. It declares motion (fitness) data and device model / OS version, linked to the participant and never used for tracking.

---

## 4. Configure your Xcode project

iOS doesn't let a library register itself for background work, so your app must declare it. **If you skip any of these, background recording silently stops working.**

### 4.1 Info.plist

| Key | Value | Why |
|---|---|---|
| `NSMotionUsageDescription` | Your wording, e.g. *"We use motion sensors to measure your walking."* | Motion & Fitness permission. Required. |
| `UIBackgroundModes` | `fetch`, `processing`, `remote-notification`, `audio` | Background extraction, uploads, silent-push wake-ups, and keeping walk tests recording with the screen locked. |
| `BGTaskSchedulerPermittedIdentifiers` | `$(PRODUCT_BUNDLE_IDENTIFIER).refresh`<br>`$(PRODUCT_BUNDLE_IDENTIFIER).processing`<br>`$(PRODUCT_BUNDLE_IDENTIFIER).overnight` | The SDK's background tasks. They must be exactly these, built from **your** bundle ID. |

As XML:

```xml
<key>NSMotionUsageDescription</key>
<string>We use motion sensors to measure your walking.</string>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
    <string>remote-notification</string>
    <string>audio</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER).refresh</string>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER).processing</string>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER).overnight</string>
</array>
```

### 4.2 Capabilities

In **Signing & Capabilities**, add **Push Notifications** and **Background Modes** (tick the four modes above).

### 4.3 App Store review: the `audio` background mode

The SDK plays **silent audio** while a manual recording or a walk test is running, so the recording continues while the screen is locked. Background tracking doesn't use it. Reviewers may ask why an app that plays no sound declares `audio`. In **App Review Information → Notes**, explain:

> *"The app records a timed walking test (6 minutes) using the motion sensors. To keep recording while the phone is locked in the user's pocket, the embedded Kinetikos SDK plays silent audio only while a test is running. No audio is played or recorded otherwise."*

---

## 5. Code

### 5.1 App delegate

The SDK needs four system events. In a SwiftUI app, add an app delegate with `@UIApplicationDelegateAdaptor`.

```swift
import UIKit
import TrackerSDK

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 1. Before anything else. Also runs when iOS launches the app in the background.
        Tracker.configure(environment: .production, tokenProvider: ParticipantTokens.fetch)

        // 2. Must be here: iOS refuses background-task registrations after launch.
        Tracker.registerBackgroundTasks()

        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Tracker.setPushToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let state = application.applicationState
        Task {
            if let result = await Tracker.handleRemoteNotification(userInfo, applicationState: state) {
                completionHandler(result)        // a Kinetikos push
            } else {
                completionHandler(.noData)       // yours: handle it as you already do
            }
        }
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        if !Tracker.handleBackgroundSession(identifier: identifier, completion: completionHandler) {
            completionHandler()                  // not the SDK's session
        }
    }
}
```

```swift
@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { WindowGroup { RootView() } }
}
```

Use `.development` or `.staging` while testing, with the credentials Kinetikos gives you for that environment (§1). `.custom(URL)` points at any other Kinetikos backend you are given. The same SDK version works with every environment.

### 5.2 The token provider

The SDK calls your `tokenProvider` whenever it needs a token, including **when the app was woken in the background with no UI** (a silent push or background task gives about 30 seconds). It must:

- return a participant token from your backend (§2.3), using the session your app keeps, e.g. a refresh token in the keychain;
- when `forceRefresh` is `true`, fetch a **new** token instead of returning a cached one: the SDK passes it after Kinetikos refused the last token (it expired), and then retries the request once;
- **never show UI** or wait for the user to sign in;
- return `nil` when nobody is signed in to your app;
- throw for a temporary failure (offline, timeout). The SDK keeps recording and tries again later.

```swift
enum ParticipantTokens {
    /// TrackerTokenProvider: `@Sendable (_ forceRefresh: Bool) async throws -> String?`
    @Sendable static func fetch(forceRefresh: Bool) async throws -> String? {
        guard let session = MyAuth.storedSession() else { return nil }   // nobody signed in
        if !forceRefresh, let cached = TokenCache.valid() { return cached } // still good for a while
        let token = try await MyBackend.participantToken(using: session)   // your §2.3 endpoint
        TokenCache.store(token)
        return token
    }
}
```

The SDK reads which participant a token is for. **If a token is for a different person than before, the SDK first deletes everything the previous person left on the phone**, so data can never go up under the wrong person.

### 5.3 Consent

Nothing is recorded until the person gives consent in your app. Show the SDK's consent text, with a checkbox for the declaration, and record the agreement:

```swift
let document = Tracker.consentDocument(locale: Locale.current.language.languageCode?.identifier ?? "en")
// Show document.text (paragraphs separated by a blank line),
// and a checkbox labelled document.declaration. Enable "I agree" once it's ticked.

// On "I agree":
let recorded = await Tracker.giveConsent(version: document.version, locale: document.locale)
// false = no participant yet: your tokenProvider returned nil. Make sure the user is signed in.
```

- The text is available in English and Portuguese; any other language gets English.
- Consent works offline and is sent to Kinetikos as soon as possible. Uploads wait until Kinetikos has received it.
- `Tracker.withdrawConsent()` records a withdrawal: recording stops at once. The person can consent again later. Offer it somewhere in your settings.

### 5.4 Permissions and tracking

After consent, ask for the Motion & Fitness permission, then start tracking:

```swift
let granted = await Tracker.requestPermissions()    // shows the system prompt if needed
await Tracker.startTracking()
```

- The SDK **never prompts on its own**; you decide when. `Tracker.permissions()` tells you what's granted. If the person denied it, send them to Settings (`UIApplication.openSettingsURLString`).
- `startTracking()` is remembered across launches and reboots. It's safe, and recommended, to call it on every launch once the person is signed in.
- `stopTracking()` pauses background recording without withdrawing consent.

*Not available yet: per-integrator silent pushes.* Kinetikos wakes phones with silent pushes so background recording keeps going, and that needs pushes signed with **your** APNs key. Until that's supported, the SDK relies on iOS background tasks alone. Recording still works, but iOS runs those tasks less often when the app isn't opened. Keep the push code from §5.1 in place: it starts working without an app update.

### 5.5 Manual recording and the 6-minute walk test

```swift
await Tracker.startWalkTest()          // false if something is already recording
await Tracker.stopWalkTest()           // stopping early discards the test

await Tracker.startManualRecording()   // the person stops it themselves
await Tracker.stopManualRecording()    // saved and uploaded
```

The walk test runs for `Tracker.walkTestDurationSeconds` (6 minutes) and fails if the person stops moving for `Tracker.walkTestIdleTimeoutSeconds` (45 seconds). Only a completed test is uploaded.

### 5.6 Status and events

```swift
// Follow the status, e.g. in a view model:
for await status in Tracker.statusUpdates() {
    switch status.state {
    case .needsConsent:     showConsent()
    case .needsPermissions: showPermissionHelp()
    case .revoked:          showNoLongerTracked()
    case .studyInactive:    showStudyNotActive()
    case .withdrawn:        showConsentWithdrawn()
    case .active, .stopped, .signedOut, .notConfigured: break
    }
    countdown = status.walkTest.remainingSeconds   // while status.walkTest.running
}

// One-off events:
for await event in Tracker.events() {
    if case .walkTestFinished(let outcome) = event { showResult(outcome) }
}
```

`state` reports the first thing in the way, in this order: `notConfigured`, `signedOut`, `revoked`, `studyInactive`, `withdrawn`, `needsConsent`, `needsPermissions`, `stopped`, `active`. `status.sync` tells you how many recordings are waiting to upload and when the last upload happened. `walkTest.remainingSeconds` is computed when you read it, so refresh it every second to show a countdown.

### 5.7 Sync and mobile data

The SDK uploads by itself, on Wi-Fi by default. `Tracker.setAllowCellular(true)` lets it use mobile data; `Tracker.allowCellular` reads the current setting, for your own toggle. `await Tracker.syncNow()` uploads now, e.g. from a "Sync" button.

### 5.8 Sign-out

Call it when the person signs out of **your** app, **before** your own sign-out, so a last upload can still get a token:

```swift
await Tracker.signOut()
await MyAuth.signOut()
```

The SDK stops, spends up to 5 seconds uploading what's pending, then stops sending anything. What couldn't be sent stays on the phone:
- **The same person signs in again:** it uploads.
- **Someone else signs in:** it's deleted before their first token is used.
- **Nobody signs back in:** it's deleted after 90 days.

Call `startTracking()` again after the next sign-in.

---

## 6. What the SDK does on its own

| Situation | What happens |
|---|---|
| Revoked by your backend | Recording stops; what wasn't sent is deleted; `state` is `revoked`, and the `revoked` event fires. A new invitation brings the person back: they keep their history but must give consent again (`needsConsent`). |
| Institution suspended, or the study ended | Recording and uploads stop; what was recorded before stays on the phone. `state` is `studyInactive`, and the `studyInactive` event fires. The SDK checks every 15 minutes or so while it runs, and when the institution is active again everything resumes by itself, with no new sign-in. |
| Consent withdrawn (in your app, or by Kinetikos staff) | Recording stops; anything recorded after the withdrawal is deleted unsent. `state` is `withdrawn`. |
| Offline | Recordings are kept and uploaded later. |
| `tokenProvider` returns `nil` or throws | Recording continues if it was on; uploads wait. |
| A different person's token | The previous person's data on the phone is deleted first. |
| App closed, or the phone restarted | Background recording continues: iOS keeps the motion data and the SDK collects it on its next wake. |

---

## 7. Testing

- **Use a real iPhone.** The simulator has no motion recorder, so background recording can't be tested there.
- Point the SDK at `.development` or `.staging`, with a test tenant and that environment's credentials from Kinetikos.
- Background work isn't immediate: iOS decides when background tasks run. Open the app to trigger an upload, or call `syncNow()`.
- Walk to test passive recording: walking periods are detected by iOS and collected later, not live.

## 8. Checklist

- [ ] Backend: client credentials stored server-side; invite; participant-token endpoint for your app; revoke.
- [ ] Package added; `import TrackerSDK`.
- [ ] Info.plist: `NSMotionUsageDescription`, four `UIBackgroundModes`, three `BGTaskSchedulerPermittedIdentifiers`.
- [ ] Capabilities: Push Notifications, Background Modes.
- [ ] App delegate: `configure`, `registerBackgroundTasks`, push token, remote notification, background session.
- [ ] `tokenProvider` works in the background without UI; returns `nil` when signed out.
- [ ] Consent screen with `consentDocument` and `giveConsent`; withdrawal in settings.
- [ ] `requestPermissions`, then `startTracking` on every launch while signed in.
- [ ] `signOut()` before your own sign-out.
- [ ] App Review note about the `audio` background mode.
- [ ] Tested on a real iPhone against development or staging.
