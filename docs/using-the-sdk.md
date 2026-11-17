# Using the SDK

[← Kinetikos Tracker SDK for iOS](../README.md)

Everything `Tracker` does, once the [quick start](../README.md) is in place. All calls are on `Tracker`, after `import TrackerSDK`.

- [Environments](#environments)
- [Why each project setting](#why-each-project-setting)
- [The token provider](#the-token-provider)
- [Consent](#consent)
- [Permissions and tracking](#permissions-and-tracking)
- [Recording a walk and the 6-minute walk test](#recording-a-walk-and-the-6-minute-walk-test)
- [Status and events](#status-and-events)
- [Uploads and mobile data](#uploads-and-mobile-data)
- [Sign-out](#sign-out)
- [What the SDK does on its own](#what-the-sdk-does-on-its-own)

## Environments

`Tracker.configure(environment:tokenProvider:)` takes `.production`, `.development` or `.staging`. Use `.development` or `.staging` while testing, with the credentials Kinetikos gives you for that environment ([which backend](backend.md#which-backend)). `.custom(URL)` points at any other Kinetikos backend you are given. The same SDK version works with every environment.

## Why each project setting

iOS doesn't let a library register itself for background work, so your app declares it (step 2 of the [quick start](../README.md#2-paste-the-project-settings)):

| Info.plist key | Value | Why |
|---|---|---|
| `NSMotionUsageDescription` | Your wording | The Motion & Fitness permission prompt. Required. |
| `UIBackgroundModes` | `fetch`, `processing`, `remote-notification`, `audio` | Collecting walking in the background, uploads, silent-push wake-ups, and keeping a walk test recording with the screen locked (see [App Store review](going-live.md#app-store-review-the-audio-background-mode)). |
| `BGTaskSchedulerPermittedIdentifiers` | `$(PRODUCT_BUNDLE_IDENTIFIER).refresh`, `.processing`, `.overnight` | The SDK's background tasks. They must be exactly these, built from **your** bundle ID. |

The SDK is a pre-built binary framework (`TrackerSDK.xcframework`) with no dependencies of its own; Xcode checks its checksum and signature when it downloads it.

## The token provider

The SDK calls your `tokenProvider` whenever it needs a token, including **when the app was woken in the background with no UI** (a silent push or background task gives about 30 seconds). It must:

- return a participant token from your server ([Your backend](backend.md#3-give-your-app-participant-tokens)), using the session your app keeps, e.g. a refresh token in the keychain;
- when `forceRefresh` is `true`, fetch a **new** token instead of returning a cached one: the SDK passes it after Kinetikos refused the last token (it expired), and then retries the request once;
- **never show UI** or wait for the user to sign in;
- return `nil` when nobody is signed in to your app;
- throw for a temporary failure (offline, timeout). The SDK keeps recording and tries again later.

```swift
enum ParticipantTokens {
    /// TrackerTokenProvider: `@Sendable @concurrent (_ forceRefresh: Bool) async throws -> String?`
    @Sendable static func fetch(forceRefresh: Bool) async throws -> String? {
        guard let session = MyAuth.storedSession() else { return nil }   // nobody signed in
        if !forceRefresh, let cached = TokenCache.valid() { return cached } // still good for a while
        let token = try await MyBackend.participantToken(using: session)   // your server's token endpoint
        TokenCache.store(token)
        return token
    }
}
```

The SDK reads which participant a token is for. **If a token is for a different person than before, the SDK first deletes everything the previous person left on the phone**, so data can never go up under the wrong person.

## Consent

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

A ready-made Consent screen: [Screens you can copy](screens.md#4-consent).

## Permissions and tracking

After consent, ask for the Motion & Fitness permission, then start tracking:

```swift
let granted = await Tracker.requestPermissions()    // shows the system prompt if needed
await Tracker.startTracking()
```

- The SDK **never prompts on its own**; you decide when. `Tracker.permissions()` tells you what's granted. If the person denied it, send them to Settings (`UIApplication.openSettingsURLString`).
- `startTracking()` is remembered across launches and reboots. It's safe, and recommended, to call it on every launch once the person is signed in.
- `stopTracking()` pauses background recording without withdrawing consent.
- Turning off Motion & Fitness after granting it is a **withdrawal** of consent ([what happens](#what-the-sdk-does-on-its-own)), not a pause: say so near your permission settings, and ask for consent again when `state` is `withdrawn`. Asking for the permission *before* recording consent, as Kinetikos' app does, keeps a consent off Kinetikos' ledger for someone who then refuses it.

*Not available yet: per-integrator silent pushes.* Kinetikos wakes phones with silent pushes so background recording keeps going, and that needs pushes signed with **your** APNs key. Until that's supported, the SDK relies on iOS background tasks alone. Recording still works, but iOS runs those tasks less often when the app isn't opened. Keep the push code from the app delegate in place: it starts working without an app update. When it's available, Kinetikos will ask you for your APNs key (`.p8`), its key ID and your team ID.

## Recording a walk and the 6-minute walk test

```swift
await Tracker.startWalkTest()          // false if something is already recording
await Tracker.stopWalkTest()           // stopping early discards the test

await Tracker.startManualRecording()   // the person stops it themselves
await Tracker.stopManualRecording()    // saved and uploaded
```

The walk test runs for `Tracker.walkTestDurationSeconds` (6 minutes) and fails if the person stops moving for `Tracker.walkTestIdleTimeoutSeconds` (45 seconds). Only a completed test is uploaded.

## Status and events

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

## Uploads and mobile data

The SDK uploads by itself, on Wi-Fi by default. `Tracker.setAllowCellular(true)` lets it use mobile data; `Tracker.allowCellular` reads the current setting, for your own toggle. `await Tracker.syncNow()` uploads now, e.g. from a "Sync" button, and asks Kinetikos for the participant's Consent first.

## Sign-out

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

## What the SDK does on its own

| Situation | What happens |
|---|---|
| Revoked by your server | Recording stops; what wasn't sent is deleted; `state` is `revoked`, and the `revoked` event fires. A new invitation brings the person back: they keep their history but must give consent again (`needsConsent`). |
| Institution suspended, or the study ended | Recording and uploads stop; what was recorded before stays on the phone. `state` is `studyInactive`, and the `studyInactive` event fires. The SDK checks every 15 minutes or so while it runs, and when the institution is active again everything resumes by itself, with no new sign-in. |
| Consent withdrawn (in your app, or by Kinetikos staff) | Recording stops; anything recorded after the withdrawal is deleted unsent. `state` is `withdrawn`. |
| Motion & Fitness turned off after it was granted with consent | That is a withdrawal, recorded and sent to Kinetikos like `withdrawConsent()`, the next time the SDK runs (any launch, or the app coming to the foreground). `state` is `withdrawn` and the `consentWithdrawn` event fires. Turning the permission back on doesn't restore consent: show your Consent screen again. |
| Offline | Recordings are kept and uploaded later. |
| `tokenProvider` returns `nil` or throws | Recording continues if it was on; uploads wait. |
| A different person's token | The previous person's data on the phone is deleted first. |
| App closed, or the phone restarted | Background recording continues: iOS keeps the motion data and the SDK collects it on its next wake. |
