# Cue Mini

A macOS menu-bar app that identifies the song playing through your microphone using ShazamKit.

Tap the tray icon (or press ⌥Space), hit "Listen", and Cue Mini will tell you what's playing.

<img width="2700" height="1674" alt="IMG_2036" src="https://github.com/user-attachments/assets/06c4a484-b6c1-4833-aab2-e88ffc1a2cf3" />


https://github.com/user-attachments/assets/4918bb59-719e-40a1-9490-beefc12252b5

DOWNLOAD NOW: https://github.com/Joseph-Rus/cue-mini/releases/tag/cue-mini



## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.10+
- A paid Apple Developer Program membership (required for ShazamKit entitlement) — Cue Mini will run locally without one, but won't be able to match against Shazam's catalog when distributed.

## Develop

```bash
# Open in Xcode
open Package.swift

# Or build/run from CLI
swift run
```

The first launch will prompt for microphone access.

## Build a distributable .app

```bash
# Debug build, ad-hoc signed (runs only on your machine)
./scripts/build-app.sh

# Release build, universal binary, ad-hoc signed
./scripts/build-app.sh --release

# Release build, signed with your Developer ID
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/build-app.sh --release
```

The result is `build/Cue Mini.app`.

## Provisioning ShazamKit

1. In [Apple Developer → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), create an App ID with bundle identifier `com.josephrussell.cuemini` (or whatever you set in [Resources/Info.plist](Resources/Info.plist)).
2. Under **App Services**, enable **ShazamKit**.
3. Generate a provisioning profile that includes the entitlement.
4. Sign the app with your Developer ID (see above).
5. Notarize for distribution outside the Mac App Store:
   ```bash
   xcrun notarytool submit "build/Cue Mini.app.zip" \
     --apple-id you@example.com --team-id TEAMID --password app-specific-pw \
     --wait
   xcrun stapler staple "build/Cue Mini.app"
   ```

## Project layout

```
Package.swift                  Swift package manifest
Sources/CueMini/
  CueMiniApp.swift             @main + MenuBarExtra
  AppState.swift               State machine (idle/listening/matched/noMatch/error)
  Settings.swift               @AppStorage-backed settings
  ShazamRecognizer.swift       SHSession + AVAudioEngine wiring
  AudioDevices.swift           CoreAudio input device enumeration
  HotkeyManager.swift          Carbon ⌥Space global hotkey
  PopoverView.swift            Pill UI
  SettingsView.swift           Settings panel
Resources/
  Info.plist                   Bundle metadata + mic usage description
  CueMini.entitlements         Sandbox + ShazamKit + audio-input
scripts/
  build-app.sh                 Bundles the binary into a .app
```
