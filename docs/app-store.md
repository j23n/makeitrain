# App Store

What's in place for submitting the Mac and iOS apps, and what's left to do by hand.

## In the project

| Item | Where |
| --- | --- |
| App icons | `Mac/Assets.xcassets/AppIcon.appiconset` (16 to 512 points at 1x and 2x) and `iOS/Assets.xcassets/AppIcon.appiconset` (1024 pixels) |
| Privacy manifests | `Mac/PrivacyInfo.xcprivacy` and `iOS/PrivacyInfo.xcprivacy` |
| Sandbox and iCloud | `Mac/TimeTracker.entitlements` and `iOS/TimeTracker.entitlements` |
| iCloud Drive folder | `NSUbiquitousContainers` in both `Info.plist` files, so the data shows as "Time Tracker" in Finder and Files |
| Category | Productivity (`LSApplicationCategoryType`, Mac) |
| Encryption | `ITSAppUsesNonExemptEncryption` is `NO` in both apps, so App Store Connect doesn't ask about export compliance |
| Launch at login | Off until the user turns it on in Settings, as guideline 2.4.5 requires |

Both apps use the bundle identifier `com.j23n.TimeTracker`, so one App Store record can offer them as a universal purchase.

## Privacy

For App Store Connect's App Privacy section, answer that the app doesn't collect data. That gives the label **Data Not Collected**:

- The apps never use the network. The Mac app's sandbox has no outgoing-network entitlement, and iCloud Drive syncs the data folder on its own.
- Entries, projects and backups stay on the device or in the user's own iCloud Drive, where the developer can't see them.
- There's no analytics, crash reporting SDK, advertising or tracking.

The privacy manifests say the same: no tracking, no tracking domains and no collected data. They declare one required-reason API: `UserDefaults`, with reason `CA92.1`, for settings only this app reads, such as where the data lives, the first day of the week and which panels are shown.

## Notes for App Review

> Time Tracker is a menu bar app on the Mac. After it opens, click the stopwatch icon in the menu bar to start, stop and switch timers. "Open Time Tracker" in that menu opens the main window with the timeline, entries, reports, and clients and projects; the app shows a Dock icon only while that window or Settings is open.
>
> No account is needed. Data is saved as JSON files in the user's iCloud Drive, in a "Time Tracker" folder, or on the device when iCloud is off. Reports can be exported as CSV through the save dialog on the Mac and the share sheet on iOS.
>
> Launch at login is off until the user turns it on in Settings.

## Left to do

1. Pick a team for both targets under Signing & Capabilities.
2. Register the App ID and the iCloud container `iCloud.com.j23n.TimeTracker` in the developer account, and turn on iCloud Documents for the App ID. If the container name changes, change it in both entitlements files, both `Info.plist` files and `AppEnvironment.live(containerIdentifier:)`.
3. Create the app in App Store Connect with the Mac and iOS platforms, and fill in the description, keywords, support URL and privacy policy URL. A short privacy policy can say what the Privacy section above says.
4. Take screenshots: the menu bar popover, the timeline, the entries table and a report on the Mac; the timer, entries and a report on iPhone and iPad.
5. Test iCloud on two devices before the first release. [Sync](sync.md) has a checklist.
6. Archive each scheme in Xcode and upload it from the Organizer.
