# Behavior

The rules the app follows, whichever screen or device an edit comes from. One timer runs at a time, entries may overlap but are flagged, and report totals count every entry in full.

## Timer

- Starting a timer stops the running one at the same instant, so switching tasks leaves no gap and no overlap.
- A quick start needs only a note. The entry shows as "Unassigned" until it gets a project.
- "Started Earlier…" moves the running timer's start back, for work that began before the timer did. This can create an overlap.
- "Stop at an Earlier Time…" stops the running timer in the past, for a timer left running. There's no idle detection.
- A stopped entry never runs again; continuing work starts a new entry. That's what lets a stop win over edits made to an out-of-date copy on another device. Undoing a stop is the one exception: it resumes the timer.
- Start and end times are whole seconds. The timeline snaps them to five minutes.
- The menu bar shows the running timer's hours and minutes, updated when the minute changes.

## Overlaps

- Overlaps are worked out when the data is displayed and never stored. Entries are scanned in order of start while tracking the latest end so far, and an entry overlaps if it starts before that end. That also catches an entry that overlaps an earlier, longer one with a shorter entry in between.
- A running timer counts as ending now. Deleted entries and entries with no duration are ignored.
- The entries table shows a warning icon and can show only overlapping entries. The timeline gives overlapping blocks an orange edge.
- Each overlap offers a one-click fix, never applied on its own. If the earlier entry ends inside the later one, the fix is "Trim Earlier Entry". If one entry contains the other, it's "Split Entry Around It", which cuts the outer entry into the parts before and after the inner one; that also covers a meeting added in the middle of a running timer. Entries that start at the same moment get no fix.

## Clients and projects

- A project without a client is listed under "No client".
- Pickers show "Acme › Website redesign"; a project without a client has no prefix.
- Typing in a project picker narrows the list to projects whose client or project name has each word typed, ignoring case and accents: "web", "site" and "acme web" all find "Acme › Website redesign". Projects whose name starts with what's typed come first. On the Mac, the arrow keys move through the list, Return picks, and Escape clears the search or closes the list.
- Archiving a client hides it and its projects from pickers and the menu bar's "Switch to" list. Their history stays in reports.
- Deleting a client or project that has entries isn't possible; the app offers to archive it instead. A client has entries when any of its projects does. Deleting a client deletes its projects too.
- Another device may still log time to a project deleted here. An entry pointing at a deleted project shows that project as archived, and so does a project whose client was deleted.
- "Merge Into…" moves every entry of one project to another, or every project of one client to another, and deletes the first. It's for when two devices each added "Acme".
- Entries point at the project, not the client, so moving a project to another client moves its history too, including in past reports.

## Tags

- Tags are free text on each entry. Extra spaces are trimmed, matching ignores case, and typing suggests existing tags with their existing spelling.
- `;` separates tags in the CSV, so the tag field drops it.
- Renaming a tag changes it on every entry. Renaming it to another tag's name merges the two. A tag can also be removed from every entry.

## Time zones

- Each entry keeps the time zone it was recorded in. It's shown and edited in that zone, with a label such as "EDT" where that isn't the device's current zone.
- An entry belongs to the day it started on, in its own zone. Reports cover calendar days: an entry is in range when its day is.
- An entry that runs past midnight counts in full on its first day, in totals and the chart alike, so the chart adds up to the total.
- The timeline draws each entry at its own wall-clock time. On a travel day blocks can look as if they overlap when they don't; overlap warnings use real time.

## Reports

- A report covers a day, a week, a month or a custom range; the iOS app offers the first three. Weeks start on the day chosen in Settings.
- Groups: by client, with each client's projects under it, then "No client" and "Unassigned"; by project; or by tag, then "Untagged". An entry with two tags counts in full under each, so tag totals can add up to more than the total.
- Filters for clients, projects and tags on the Mac.
- Every entry counts in full, so the total equals the sum of end minus start over the CSV's rows. Where entries overlap, that time counts twice, and the report says how much: the sum of the durations minus the length of their union, which stays right when three entries overlap.
- A running timer isn't in the totals or the CSV. Reports show it on its own line, such as "Running: 0:42, not included".
- While iCloud files are still downloading or a file can't be read, reports say their totals may be incomplete.

## CSV export

The CSV has the entries behind the report: the same range and filters, one row each, whatever the grouping.

```csv
date,start,end,hours,client,project,tags,note
2026-09-23,2026-09-23T09:15:00+02:00,2026-09-23T11:40:00+02:00,2.4167,Acme,Website redesign,design;client-call,"Wireframe review, round 2"
2026-09-23,2026-09-23T13:00:00+02:00,2026-09-23T14:30:00+02:00,1.5000,,Internal tooling,,Release script
```

- UTF-8 with a byte-order mark, which Excel needs to read accented characters. Lines end in CRLF, and fields with commas, quotes or line breaks are quoted.
- `date` is the entry's day in its own time zone. `start` and `end` are ISO 8601 with the entry's own offset.
- `hours` has four decimals, because spreadsheets can't add up the ISO times. The column adds up to within seconds of the report total.
- Tags are joined with `;`. A project without a client has an empty client cell; an unassigned entry has empty client and project cells.
- On the Mac the file is saved through the save dialog, which gives the sandboxed app access to the chosen file. On iOS it goes to the share sheet.

## Undo

Every edit can be undone and redone from the Edit menu, or by shaking an iPhone. An undo is saved and synced like any other edit.
