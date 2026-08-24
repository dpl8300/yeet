# YEET technical spike

YEET is currently a deliberately minimal SwiftUI/Core Motion experiment for measuring iPhone airtime. It has no persistence, account, backend, leaderboard, camera, sharing, analytics, or production visual design.

## Run on an iPhone

1. Open `YEET.xcodeproj` in Xcode 26.6 or newer.
2. In the YEET target's Signing & Capabilities pane, select your development team. Change `com.dpl8300.yeet` only if that identifier is unavailable to the team.
3. Connect an iPhone running iOS 18 or newer, enable Developer Mode, select it as the run destination, and run the `YEET` scheme.
4. Tap **Start YEET** and make only low, controlled tosses over a bed or couch, with a case fitted and the area clear.

The simulator is useful for UI and synthetic tests, but it cannot validate live freefall detection.

## Verify

```sh
xcodebuild -project YEET.xcodeproj \
  -scheme YEET \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Initial detector values live only in `DetectionConfig.spikeV1`. Airtime uses the first confirmed low-g sample and first confirmed landing-exit sample's Core Motion timestamps; confirmation latency is not added to the result.

## Calibrate

DEBUG builds show a throttled sensor panel. State changes and threshold crossings use unified logging. When a detector session finishes or is rejected, the Xcode console prints a `YEET_TRACE_BEGIN`/`YEET_TRACE_END` CSV block containing the full in-memory sensor trace. Use that trace to tune one category of values at a time, then replay representative sequences through the unit tests.
