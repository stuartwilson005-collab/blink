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

Select the BlinkControl scheme, choose your Apple development team under Signing & Capabilities, and use a unique bundle ID if necessary. Run on an iPhone or simulator. Sign in with Blink in the hosted sign-in screen, completing any MFA steps there. Passwords are never stored by this app. Access and refresh tokens are stored in the device Keychain, available after the first device unlock following a restart and not migrated to another device. This allows the paired Watch to request controls while the iPhone is locked. Existing sessions are migrated to that Keychain policy when loaded. Sign out deletes the local session; it does not revoke all Blink sessions remotely.

The Xcode project is generated and ignored; `project.yml` is its source of truth. No third-party Swift dependencies are required. The generated iPhone app embeds the companion Watch app. Existing isolated checkouts are sufficient; no worktree is needed.

## iPhone Shortcuts

After signing in, create a shortcut in Apple Shortcuts, search for **Blink Control**, and add:

- **Set Camera Motion**: select a camera (system names distinguish duplicates) and explicitly choose Enabled on or off.
- **Set System Armed**: select a system and explicitly choose Armed on or off.

Use separate enable/disable shortcuts for predictable outcomes. To enable effective motion detection, enable the camera and arm its system. Add a shortcut to the Home Screen from its menu, or assign it in iPhone Settings to the Action Button or Back Tap. Actions require device authentication and an internet connection; locked-device silent execution is not supported. Each action fetches current device identity and verifies the resulting state before reporting success. App status refreshes on returning to the foreground after a shortcut.

## Validation

```sh
swift test
xcodegen generate
xcodebuild -project BlinkControl.xcodeproj -scheme BlinkControl -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO build
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

## Apple Watch: arm/disarm from your wrist

The companion app requires **watchOS 10+** and the paired iPhone app on **iOS 17+**. Sign in on the iPhone; no Watch login is needed. The Watch lists every system with its last reported armed state, connectivity, camera count and refresh time. Use **Arm system** or **Disarm system** (with confirmation) for each system. Camera motion preferences are left unchanged.

This is an **iPhone-connected companion**, not standalone cellular/Wi-Fi Blink access. The phone performs Blink requests over WatchConnectivity, confirms the resulting state and returns it to the Watch. Passwords and access/refresh tokens stay on the phone. Only system names, IDs, statuses, counts and timestamps are sent to the Watch. The iPhone needs internet and must be reachable; unlock once after each phone restart and open Blink Control if connection fails. A locked phone is intended to work after that first unlock, subject to watchOS/iOS background execution. Force-quitting the phone app can prevent connectivity.

Commands are immediate messages and are never queued for later execution. A lost connection can happen after Blink has accepted a command: the Watch reports that uncertainty and asks you to refresh, rather than retrying automatically. Cached statuses carry timestamps and become visibly stale after a minute. Signing out on iPhone clears the Watch's status when the next context or response arrives; offline Watch status may remain visible with its old timestamp until reconnected.

### Run with simulators on your Mac

1. Preserve any local edits (such as `view.isInspectable = true`) before pulling. Run `git pull`, then `xcodegen generate` in the checkout.
2. In Xcode **Settings → Components**, install iOS and watchOS simulator runtimes if needed.
3. In **Window → Devices and Simulators → Simulators**, create/select an Apple Watch simulator paired with your iPhone simulator. Exact pairing controls vary with Xcode versions.
4. Select **BlinkControl**, run on the paired iPhone simulator and sign in. Leave the app running for the first connectivity test.
5. Select the **BlinkControlWatch** scheme, choose the paired Watch simulator and run.
6. Open the Watch app, tap Refresh, and compare all systems with the phone. Arm a test system, verify it in the official Blink app, then disarm and verify again.

For a physical Watch, set the same development team on both app targets, install the iPhone app and then install Blink Control through the iPhone's Watch app if it isn't installed automatically. If you change the phone's bundle identifier, also change the Watch identifier so it has the phone identifier as its prefix, and update `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` in `project.yml` to exactly match the phone identifier.

### Watch validation

```sh
swift test
xcodegen generate
xcodebuild -project BlinkControl.xcodeproj -scheme BlinkControlWatch -destination 'generic/platform=watchOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Core tests cover Watch command encoding, explicit desired states, rejection of unknown/malformed commands, unknown versus disarmed states, sign-out clearing and error replies. Both simulator builds are configured in CI. WatchConnectivity and native Watch compilation cannot be validated in the Linux cloud workspace and require Xcode.

Device acceptance checks: compare multiple systems (including duplicate names and unknown state), confirm arm/disarm and cancellation, try overlapping phone/Watch operations, disconnect during a command, force-quit the iPhone app, lock and restart the phone, let status become stale, sign out/re-sign in, and verify camera motion settings remain unchanged. The original iPhone app sign-in and camera controls were reported working by the user in the simulator; the new Watch integration still needs native build and paired-device validation.
