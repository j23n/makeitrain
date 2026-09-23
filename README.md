# Time Tracker

A native SwiftUI time tracker for the Mac, with iPhone and iPad later. It keeps
everything in readable JSON files, in iCloud Drive or a local folder, and never
touches the network. [PLAN.md](PLAN.md) has the design and the build order.

## Layout

- `TrackerCore/` is a Swift package with the models, the file format, merging,
  the two-timers rule, overlap detection and the file store. It has no UI code
  and builds on macOS, iOS and Linux.

## Tests

```sh
swift test --package-path TrackerCore
```

GitHub Actions runs them on macOS and Linux for every push.
