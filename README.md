# Time Tracker

A menu bar time tracker for the Mac, with an iPhone and iPad app. You start, switch, stop and log time by typing a line, such as `web #12 fix login from 9:30`, and the week shows what needs correcting, such as overlaps and timers left running, with a fix for each. It keeps everything in readable JSON files, in iCloud Drive or a local folder, and never touches the network.

## Building

You need Xcode 16 or later.

1. Open `TimeTracker.xcodeproj`.
2. Pick your team under Signing & Capabilities. The app uses the iCloud container `iCloud.com.j23n.TimeTracker`; change it in both entitlements files and in `Info.plist` if you use a different one.
3. Run the `TimeTracker` scheme with My Mac, an iPhone or an iPad as the destination. It's one target that builds the Mac app and the iPhone and iPad app, and on iOS the widget extension with the Live Activity and controls.

## Tests

```sh
swift test --package-path Packages/TrackerCore
swift test --package-path Packages/TrackerKit
```

GitHub Actions runs both on macOS, runs TrackerCore on Linux too, and builds the app for macOS and iOS.

## Previews

Every screen has SwiftUI previews, in Debug builds only. They show a week of sample data, `PreviewData` in TrackerKit: two clients, a running timer, an overlap, an unassigned entry, an entry recorded in New York and an archived project, with "now" fixed at Wednesday, September 23, 2026, 15:40 in Berlin. Some also show a freelancer's three months, two clients with a project each, hundreds of hours and dozens of tags that refer to issues, written like `Core/#131`, to see long totals and long lists of tags. The previews read no files, and edits made in a live preview go to a temporary folder.

To see them, open `TimeTracker.xcodeproj`, choose the `TimeTracker` scheme with My Mac as the destination for the Mac's screens or an iPhone or iPad for iOS's, open a view's file from the TrackerKit package, and show the canvas (Editor › Canvas, ⌥⌘↩). The wide screens in `WideUI` build for both; pick an iPad in landscape as the canvas's device to see them as a wide iPad window shows them.

## Layout

- `App/` is the app target, for macOS and iOS alike. It holds little more than the entry point, the App Shortcuts, entitlements and assets.
- `Shared/` has the App Intents, which the app and the widget extension both build, and `Widgets/` the extension: the Live Activity and the controls.
- `Packages/TrackerKit` has the app model, storage, iCloud sync and the design's parts (`TrackerKit`), the wide window's screens the Mac and a wide iPad window share (`WideUI`), the rest of the Mac app (`MacUI`), the iPhone's screens and the iOS app (`MobileUI`), and the Live Activity's attributes (`TimerActivity`).
- `Packages/TrackerCore` has the data model, file format, merging, the command line's reading, corrections and the other rules. It builds on Linux as well.

## Docs

- [Architecture](docs/architecture.md): how the pieces fit together.
- [Behavior](docs/behavior.md): the command line, the timer, corrections, editing, reports, projects, tags and GitHub links, time zones, CSV and calendars.
- [Data format](docs/data-format.md): the JSON files and what's in them.
- [Sync](docs/sync.md): merging, saving, iCloud and backups.
- [App Store](docs/app-store.md): privacy, review notes, and what's left before submitting.
