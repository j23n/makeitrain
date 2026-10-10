@.apple-ci/claude/j23n.md
@.apple-ci/claude/apps.md

# Time Tracker (makeitrain)

A menu bar time tracker for the Mac, with an iPhone and iPad app, that keeps everything in readable JSON files in iCloud Drive or a local folder (README.md). Start with the docs:

- `docs/architecture.md`: the layout, how the pieces fit, the screens, permissions and the choices behind them.
- `docs/behavior.md`: what the app does, from the command line to undo. It's the specification.
- `docs/data-format.md` and `docs/sync.md`: the files, and how they're merged and saved.

## Build and test

```sh
make test          # TrackerCore and TrackerKit (swift test for each)
make test-core     # TrackerCore alone: what runs on Linux
make build         # the app for the iOS Simulator and the Mac, unsigned
```

CI also builds and tests the packages with Xcode 16 on macOS 15, so the macOS 15 SDK must keep compiling them: guard newer APIs with `if #available` or `#if compiler(…)`. The minimum versions are macOS 14 and iOS 17.

## Code

- **Logic lives in the packages,** where `swift test` runs it; the app target stays thin. `TrackerCore` is plain Swift with no Apple-only dependencies, so it builds and tests on Linux. Keep it that way.
- **Screens and intents talk only to `AppModel`,** and only `FileStore` touches the disk (docs/architecture.md, "How the pieces fit").
- **Swift:** TrackerKit's targets use the Swift 5 language mode (`Package.swift`). Don't change a target's language mode as a side effect of another change.
- **No third-party dependencies.** FeedbackKit is the one package, in `MacUI` and `MobileUI`.
- **No network.** The apps are sandboxed without the outgoing-network entitlement. The one exception is the Mac's Debug builds, for in-app feedback (`App/TimeTracker-macOS-Debug.entitlements`). GitHub links open in the browser.
- **Previews:** every screen has SwiftUI previews with the sample data in `PreviewData`. Give a new screen previews too.
- **Feedback screenshots:** FeedbackKit's `.allContent` redaction hides every text and image. Every window's root view applies `.feedbackRedaction(Feedback.center)` (`AppScenes`, `MobileScenes`), and a new window needs it too.

## Docs

A change in behavior updates `docs/behavior.md` in the same change. A change to the files updates `docs/data-format.md`, and older files must still load.
