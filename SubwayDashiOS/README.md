# Subway Dash (iOS)

iPhone build of the Subway Dash endless runner — a SwiftUI + WKWebView shell
around the exact same Three.js game as the Android app. The Xcode project
references `../SubwayRunner/app/src/main/assets/index.html` and
`three.min.js` directly, so there is a single source of truth: edit the game
once and both the APK and the IPA pick it up.

## Getting the app on your iPhone

Every push runs the **Build IPA (unsigned)** workflow, which attaches
`SubwayDash-unsigned.ipa` to the repo's **latest** GitHub Release.

Apple does not allow installing unsigned apps directly, so sign it
on-device the same way as the other apps in this repo: download the
`.ipa` from the release page, then sign + install it with KSign
(or AltStore / Sideloadly with your Apple ID).

## Building locally

Open `SubwayDash.xcodeproj` in Xcode 15+, select your team, and run on
your device — or build unsigned from the command line:

```bash
xcodebuild -project SubwayDashiOS/SubwayDash.xcodeproj -scheme SubwayDash \
  -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```
