# App Store

What's in place for submitting the Mac and iOS apps, and what's left to do by hand. The iOS app runs on iPhone and iPad, and a wide iPad window shows the Mac's layout.

## In the project

| Item | Where |
| --- | --- |
| App icons | `App/Assets.xcassets/AppIcon.appiconset`: the Mac's at 16 to 512 points at 1x and 2x, and iOS's at 1024 pixels |
| Privacy manifest | `App/PrivacyInfo.xcprivacy`, for both platforms |
| Sandbox, iCloud and calendars | `App/TimeTracker-macOS.entitlements` and `App/TimeTracker-iOS.entitlements`, picked per platform by `CODE_SIGN_ENTITLEMENTS` |
| Calendar access | `NSCalendarsFullAccessUsageDescription` in `App/Info.plist`, shown when the app first asks to read calendars |
| Live Activity and controls | The `TimeTrackerWidgets` extension, with the bundle identifier `com.j23n.TimeTracker.Widgets`, embedded in the iOS app; `NSSupportsLiveActivities` is set for iOS |
| iCloud Drive folder | `NSUbiquitousContainers` in `App/Info.plist`, so the data shows as "Time Tracker" in Finder and Files |
| Category | Productivity (`LSApplicationCategoryType`, Mac) |
| Encryption | `ITSAppUsesNonExemptEncryption` is `NO` in both apps, so App Store Connect doesn't ask about export compliance |
| Launch at login | Off until the user turns it on in Settings, as guideline 2.4.5 requires |

The Mac and iOS apps are one target with the bundle identifier `com.j23n.TimeTracker`, so one App Store record can offer them as a universal purchase.

## Privacy

For App Store Connect's App Privacy section, answer that the app doesn't collect data. That gives the label **Data Not Collected**:

- The apps never use the network. The Mac app's sandbox has no outgoing-network entitlement, and iCloud Drive syncs the data folder on its own.
- Entries, projects and backups stay on the device or in the user's own iCloud Drive, where the developer can't see them.
- Calendars are read on the device, only those the user links to projects, and only to add their events as entries in the same data folder.
- There's no analytics, crash reporting SDK, advertising or tracking.

The privacy manifests say the same: no tracking, no tracking domains and no collected data. They declare one required-reason API: `UserDefaults`, with reason `CA92.1`, for settings only this app reads, such as where the data lives, the first day of the week, the appearance and the lines typed.

## Notes for App Review

> Time Tracker is a menu bar app on the Mac. After it opens, click the stopwatch icon in the menu bar and type a project's name, such as "website", then Return, to start a timer; "stop" stops it. "Open Time Tracker" in that menu opens the main window with the week, the month, the year, and the clients and projects; the app shows a Dock icon only while that window or Settings is open.
>
> No account is needed. Data is saved as JSON files in the user's iCloud Drive, in a "Time Tracker" folder, or on the device when iCloud is off. Reports can be saved as CSV or as a PDF statement through the save dialog on the Mac and the document picker on iOS.
>
> Launch at login is off until the user turns it on in Settings.
>
> On iPhone the app has four tabs, Today, Week, Month and Projects, with the command line over the tab bar. A wide iPad window shows the Mac's main window; a narrow one, the iPhone's tabs. While a timer runs, the iOS app shows it as a Live Activity, which Settings can turn off.
>
> Calendar access is optional. In a project's settings, or in Settings, the user picks a calendar for a project; its events that aren't logged then show in the week as corrections to log, and Settings › Import Calendar Events… adds them in one go. Nothing leaves the device.
>
> Projects can list GitHub repositories. Tags like #123 then open that issue on github.com in the browser; the app itself makes no network requests.

## Left to do

1. Pick a team for both targets under Signing & Capabilities, and check that the app shows iCloud for both platforms and the App Sandbox for macOS.
2. Register the App ID and the iCloud container `iCloud.com.j23n.TimeTracker` in the developer account, and turn on iCloud Documents for the App ID. If the container name changes, change it in both entitlements files, `App/Info.plist` and `AppEnvironment.live(containerIdentifier:)`.
3. Register the extension's App ID, `com.j23n.TimeTracker.Widgets`, too. Then create the app in App Store Connect with the Mac and iOS platforms, and fill in the description, keywords, support URL and privacy policy URL. A short privacy policy can say what the Privacy section above says.
4. Take screenshots: the menu bar popover with a line typed, the week with its corrections, the month with its statement and a project's page on the Mac; Today, the week's corrections, the month and the command line on iPhone; the week and the month on iPad; and the Live Activity on the Lock Screen.
5. Test iCloud on two devices before the first release. [Sync](sync.md) has a checklist.
6. Archive the `TimeTracker` scheme for Any Mac, and again for Any iOS Device, and upload each archive from the Organizer.
