# Time Tracker

A menu bar time tracker for the Mac, with an iPhone and iPad app. It keeps everything in readable JSON files, in iCloud Drive or a local folder, and never touches the network.

## Building

You need Xcode 16 or later.

1. Open `TimeTracker.xcodeproj`.
2. For both targets, pick your team under Signing & Capabilities. The apps use the iCloud container `iCloud.com.j23n.TimeTracker`; change it in both entitlements files and both `Info.plist` files if you use a different one.
3. Run the `TimeTracker` scheme for the Mac app, or `TimeTrackerMobile` for iPhone and iPad.

## Tests

```sh
swift test --package-path Packages/TrackerCore
swift test --package-path Packages/TrackerKit
```

GitHub Actions runs both on macOS, runs TrackerCore on Linux too, and builds both apps.

## Previews

Every screen has SwiftUI previews, in Debug builds only. They show a week of sample data, `PreviewData` in TrackerKit: two clients, a running timer, an overlap, an unassigned entry, an entry recorded in New York and an archived project, with "now" fixed at Wednesday, September 23, 2026, 15:40 in Berlin. The previews read no files, and edits made in a live preview go to a temporary folder.

To see them, open `TimeTracker.xcodeproj`, choose the `TimeTracker` scheme for the Mac screens or `TimeTrackerMobile` for iOS, open a view's file from the TrackerKit package, and show the canvas (Editor › Canvas, ⌥⌘↩).

## Layout

- `Mac/` and `iOS/` are the app targets. They hold little more than the entry point, entitlements and assets.
- `Packages/TrackerKit` has the app model, storage, iCloud sync and the views both apps share (`TrackerKit`), and each app's screens (`MacUI`, `MobileUI`).
- `Packages/TrackerCore` has the data model, file format, merging and rules. It builds on Linux as well.

## Docs

- [Architecture](docs/architecture.md): how the pieces fit together.
- [Behavior](docs/behavior.md): the timer, overlaps, projects, tags, time zones, reports and CSV.
- [Data format](docs/data-format.md): the JSON files and what's in them.
- [Sync](docs/sync.md): merging, saving, iCloud and backups.
- [App Store](docs/app-store.md): privacy, review notes, and what's left before submitting.
