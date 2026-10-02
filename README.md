# Time Tracker

A menu bar time tracker for the Mac, with an iPhone and iPad app. It keeps everything in readable JSON files, in iCloud Drive or a local folder, and never touches the network.

## Building

You need Xcode 16 or later.

1. Open `TimeTracker.xcodeproj`.
2. Pick your team under Signing & Capabilities. The app uses the iCloud container `iCloud.com.j23n.TimeTracker`; change it in both entitlements files and in `Info.plist` if you use a different one.
3. Run the `TimeTracker` scheme with My Mac, an iPhone or an iPad as the destination. It's one target that builds the Mac app and the iPhone and iPad app.

## Tests

```sh
swift test --package-path Packages/TrackerCore
swift test --package-path Packages/TrackerKit
```

GitHub Actions runs both on macOS, runs TrackerCore on Linux too, and builds the app for macOS and iOS.

## Previews

Every screen has SwiftUI previews, in Debug builds only. They show a week of sample data, `PreviewData` in TrackerKit: two clients, a running timer, an overlap, an unassigned entry, an entry recorded in New York and an archived project, with "now" fixed at Wednesday, September 23, 2026, 15:40 in Berlin. Some also show a freelancer's three months, two clients with a project each, hundreds of hours and dozens of tags that refer to issues, written like `Scheduler/#131`, to see long totals and long lists of tags. The previews read no files, and edits made in a live preview go to a temporary folder.

To see them, open `TimeTracker.xcodeproj`, choose the `TimeTracker` scheme with My Mac as the destination for the Mac's screens or an iPhone or iPad for iOS's, open a view's file from the TrackerKit package, and show the canvas (Editor › Canvas, ⌥⌘↩). The iPad's screens are in `MobileUI/Pad`; pick an iPad as the canvas's device to see them at their size.

## Layout

- `App/` is the app target, for macOS and iOS alike. It holds little more than the entry point, entitlements and assets.
- `Packages/TrackerKit` has the app model, storage, iCloud sync and the views both apps share (`TrackerKit`), and each app's screens: the Mac's (`MacUI`), and the iPhone's and iPad's (`MobileUI`).
- `Packages/TrackerCore` has the data model, file format, merging and rules. It builds on Linux as well.

## Docs

- [Architecture](docs/architecture.md): how the pieces fit together.
- [Behavior](docs/behavior.md): the timer, overlaps, projects, tags and GitHub links, time zones, reports, CSV and calendar import.
- [Data format](docs/data-format.md): the JSON files and what's in them.
- [Sync](docs/sync.md): merging, saving, iCloud and backups.
- [App Store](docs/app-store.md): privacy, review notes, and what's left before submitting.
