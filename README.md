# Blink Control

An initial native iPhone/iPad app for Blink cameras, targeting iOS 17+. It lists cameras grouped by system, shows system armed status and reported camera connectivity, battery and motion status, and provides individual motion controls and system arm/disarm controls. Status refreshes on launch, foreground, pull-to-refresh and every 30 seconds while active. Unknown values stay unknown; last-refresh times expose stale data.

**Enable/disable means motion detection**, not camera power or privacy mode. Motion detection requires an armed system as well as enabled camera motion. Disabling motion does not prevent live view. System arming does not change individual motion settings.

## Open and run on a Mac

Requirements: macOS, Xcode 15+ (Xcode 16 recommended), Swift 5.9+, and XcodeGen 2.42+.

```sh
cd /path/to/blink
brew install xcodegen # once
swift test
xcodegen generate
open BlinkControl.xcodeproj
```

Select the BlinkControl scheme, choose your Apple development team under Signing & Capabilities, and use a unique bundle ID if necessary. Run on an iPhone or simulator. Sign in with Blink in the hosted sign-in screen, completing any MFA steps there. Passwords are never stored by this app. Access and refresh tokens are stored in the device Keychain, available only while unlocked and not migrated to another device. Sign out deletes the local session; it does not revoke all Blink sessions remotely.

The Xcode project is generated and ignored; `project.yml` is its source of truth. No third-party Swift dependencies are required. Existing isolated checkouts are sufficient; no worktree is needed.

## iPhone Shortcuts

After signing in, create a shortcut in Apple Shortcuts, search for **Blink Control**, and add:

- **Set Camera Motion**: select a camera (system names distinguish duplicates) and explicitly choose Enabled on or off.
- **Set System Armed**: select a system and explicitly choose Armed on or off.

Use separate enable/disable shortcuts for predictable outcomes. To enable effective motion detection, enable the camera and arm its system. Add a shortcut to the Home Screen from its menu, or assign it in iPhone Settings to the Action Button or Back Tap. Actions require device authentication and an internet connection; locked-device silent execution is not supported. Each action fetches current device identity and verifies the resulting state before reporting success. App status refreshes on returning to the foreground after a shortcut.

## Validation

```sh
swift test
xcodegen generate
xcodebuild -project BlinkControl.xcodeproj -scheme BlinkControl -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Core tests cover all camera families, grouping and identity collisions, unknown states, missing network metadata, invalid responses, command routing and form encoding. GitHub Actions runs these tests and an unsigned iOS simulator build on macOS. Native UI, Keychain and App Intents need Xcode/device validation.

Live-account acceptance checks still required:

1. Sign in, including MFA; cancel and retry; relaunch to restore the session.
2. Compare every system and camera against the official Blink app, including offline devices and disarmed systems.
3. Change each supported camera family's motion setting and system arming; check both apps agree. Verify errors preserve the last known state and show its refresh time.
4. Create and run enable/disable shortcuts for cameras with duplicate names across systems. Confirm disarmed-system messaging, offline/network failures and expired-session errors.
5. Sign out and verify shortcuts request sign-in again.

## Integration limits

Blink has no public supported camera-control API. This implementation follows observed endpoints in the community [blinkpy](https://github.com/fronzbot/blinkpy) project (inspected 2026-10-25), with independently written Swift code. Blink may change endpoints, restrict embedded sign-in, or reject third-party clients. Hosted OAuth with PKCE, state checking and the iOS client redirect is implemented but has **not been verified with a live Blink account**. No affiliation with Amazon or Blink is implied.

Required HTTPS destinations on the iPhone: `api.oauth.blink.com`, `rest-prod.immedia-semi.com`, and the account's region host under `immedia-semi.com`; Blink's hosted login may require additional authentication destinations. No credentials belong in repository files or CI secrets for unit tests.

The Linux cloud workspace can edit this project and run core tests with a Swift toolchain. It cannot build or run Apple's iOS SDK, simulator, Keychain or App Intents. A successful core test run is not an iOS build or live-account validation.
