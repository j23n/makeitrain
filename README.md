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

## Layout

- `Mac/` and `iOS/` are the app targets. They hold little more than the entry point, entitlements and assets.
- `Packages/TrackerKit` has the app model, storage and iCloud sync (`TrackerKit`), and the screens (`MacUI`, `MobileUI`).
- `Packages/TrackerCore` has the data model, file format, merging and rules. It builds on Linux as well.

## Docs

- [Architecture](docs/architecture.md): how the pieces fit together.
- [Data format](docs/data-format.md): the JSON files and what's in them.
- [Sync](docs/sync.md): merging, saving, iCloud and backups.
