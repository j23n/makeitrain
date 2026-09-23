# Sync

Syncing is iCloud Drive moving files between devices; the app never talks to a server. Several devices write to the same folder, sometimes offline, so the app merges everything it reads, by id, without asking. Merging gives the same result in any order and however often it's repeated, which is what makes every device end up with the same data.

## Merging

- **Records:** for each id, the copy with the newest `updated` wins.
- **Ends:** an entry's `end` merges separately, by `endUpdated`. A stop made on one device therefore survives an edit made to an out-of-date copy elsewhere.
- **Ties:** copies stamped in the same millisecond are compared field by field, byte by byte, so every device picks the same winner. A copy that isn't deleted wins a tie with one that is.
- **Missing records:** a record missing from a file never means it was deleted. Only a `deleted` stamp does.
- **Clocks:** "newest wins" relies on each device's clock. An edit stamps the later of now and the previous stamp plus one millisecond, so it beats the version it was made from even when this device's clock is behind.

## Saving

- Each save reads the file as it is now, merges it with the app's records and writes the result in one step. In iCloud the whole read-merge-write runs inside one coordinated write, so changes another device made in the meantime are kept.
- The write is skipped when nothing changed.
- Only files with changes are saved. Saves wait about a second so quick edits are written together, and pending saves are written before the app quits.
- When an entry moves to another month, the new month is written first and the old one cleaned up afterwards. A crash in between leaves a duplicate, which merging handles, rather than a lost entry.

## Reading

- At launch the app reads every file and merges them by id. An entry that moved between months settles on its newest copy.
- A file that can't be read, or comes from a newer version of the app, is never overwritten. The app names it in a notice and holds back saves to that file until it can be read.
- Numbered copies such as `2026-10 2.json` are merged into the main file and then deleted. iCloud creates them when two devices each create a file with the same name before syncing, for example when both log the first entry of a month.

## iCloud

- **Watching:** a metadata query on the iCloud folder reports files changed by other devices, and files that aren't downloaded yet. The app asks iCloud to download those, and reports show that their data may be incomplete until everything has arrived. A file that isn't downloaded is never written.
- **Conflicts:** if two devices change the same file before syncing, iCloud keeps both versions. The app reads every version, merges them by id, writes the result, and marks the other versions resolved.
- **First launch:** with iCloud, the app waits for the query's first results before it creates any file, so a new Mac doesn't start a second, empty set of files.
- **Signing out:** when the Mac or iPhone signs out of iCloud, the app stops saving and keeps showing what it has, read-only. It offers to switch to local storage, which copies that data. It never silently switches to an empty local folder.

## Two running timers

Only one timer runs at a time. When two devices each start one while one of them is offline, the files end up with two running entries. The later one keeps running, and the earlier one ends at the moment the later one started. Like overlaps, this is worked out whenever the data is read, not written back, so every device shows the same thing. The earlier entry gets a real end with the next change on any device.

## Switching storage

- Turning iCloud on merges the local files into the iCloud folder by id, even when it already holds data from another device.
- Turning it off copies the iCloud files into the local folder and leaves iCloud untouched, so other devices keep syncing.
- Files are never moved out of iCloud, because that deletes them from every other device.

## Backups

Once a day, and before switching storage, the app writes a full copy of its data into `Backups/` in its Application Support folder and keeps the 30 newest. Without them, a merge bug or a damaged file could reach every device within seconds, and iCloud Drive keeps no history of plain files. Settings has a button that shows the backups in Finder.

## Checking sync on two devices

Worth doing before trusting the app with real data, and after any change to the file store:

1. Edit on both devices while one is offline, including the same entry on both, then bring it back online. Both devices should show the same result.
2. Log the first entry of a new month on both devices while one is offline. A numbered copy may appear briefly, then fold into the main file.
3. On the Mac, turn on "Optimize Mac Storage" and let iCloud remove local copies of old months. Reports for those months should download them again.
4. Sign out of iCloud on one device and check that nothing is lost and the notice appears.
5. Check that the "Time Tracker" folder shows up in Finder and in the Files app.
