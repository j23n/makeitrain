# Behavior

The rules the app follows, whichever screen or device an edit comes from. One timer runs at a time, entries may overlap but are flagged, and report totals count every entry in full.

## Timer

- Starting a timer stops the running one at the same instant, so switching tasks leaves no gap and no overlap.
- A quick start needs only a note. The entry shows as "Unassigned", with an empty ring where a project's color would be, until it gets a project. The menu bar's quick start also takes a project and tags, offering the project's tags as you type.
- The main window's toolbar has the timer in a capsule: a round button to start a timer without a project, or the running timer's project, note (or tags) and time with a round button to stop it. Its menu starts, or switches to, a recent project and tags. On macOS 26 it has as much space on its left, up to the screen's title, as on its right, up to the screen's buttons, and it's as tall as the toolbar's other items. Earlier versions of macOS center it in the part of the toolbar beside the sidebar.
- On iPad, every screen but the Timer has the timer in the middle of its toolbar: "Start Timer", or a stop button and the running timer's project and time. Touching and holding "Start Timer" offers the recent projects and tags; tapping the running timer offers them too, with "Started Earlier…" and "Stop at an Earlier Time…".
- Wherever recent projects and tags are offered, the running timer's are marked and can't be picked: starting them again would only cut the running entry in two.
- The running timer's entry has a red mark wherever entries are listed: in the Mac's table, on iPhone and iPad, on the timeline and in the month calendar. In the lists and the month calendar, an overlap's warning takes its place.
- "Started Earlier…" moves the running timer's start back, for work that began before the timer did. This can create an overlap.
- "Stop at an Earlier Time…" stops the running timer in the past, for a timer left running. There's no idle detection.
- A stopped entry never runs again; continuing work starts a new entry. That's what lets a stop win over edits made to an out-of-date copy on another device. Undoing a stop is the one exception: it resumes the timer.
- Start and end times are whole seconds. The timeline snaps them to five minutes.
- The menu bar shows the running timer's hours and minutes, updated when the minute changes.

## Overlaps

- Overlaps are worked out when the data is displayed and never stored. Entries are scanned in order of start while tracking the latest end so far, and an entry overlaps if it starts before that end. That also catches an entry that overlaps an earlier, longer one with a shorter entry in between.
- A running timer counts as ending now. Deleted entries and entries with no duration are ignored.
- The entries list and the month calendar show a warning icon, and the list's "Overlaps" filter shows only overlapping entries; right-clicking an entry on the Mac, or touching and holding it on iPad, offers its fixes. The timeline gives overlapping blocks an orange edge.
- Each overlap offers a one-click fix, never applied on its own. If the earlier entry ends inside the later one, the fix is "Trim Earlier Entry". If one entry contains the other, it's "Split Entry Around It", which cuts the outer entry into the parts before and after the inner one; that also covers a meeting added in the middle of a running timer. Entries that start at the same moment get no fix.

## Editing entries

- On the Mac and iPad, the bar over the entries narrows them to a period (today, this or last week or month, this year, or days of your choice), to clients and projects, to entries with any of some tags, and to overlaps, and shows how many entries that leaves and their total time. The tags offered are those of the projects chosen, or of all projects. "Today" and the other periods move on as the days pass; days of your choice stay. An entry is on the day it starts, in its own time zone, as in reports. The search field in the toolbar narrows it further, by note, project or tag. On iPad the entries are listed by day, newest first, and the one tapped is edited in the inspector beside the list.
- On the Mac, the entries table is edited in place, and every row shows its values as text, whatever the pointer has passed over. Start and end are in the entry's own time zone, with the zone's name next to the start when it isn't the Mac's. Clicking one makes it a field to type over, with no stepper, where clicking the date opens a calendar, and a click outside the calendar closes it and leaves the field open; Return finishes, Escape puts back what it was, and the change is made when editing ends. Clicking the tags makes them tokens to edit the same way. The end's tooltip says how long the entry is. Click the project to choose another, and the note to type over it. On the timeline, the selected entry is edited in the inspector, which also takes a duration.
- On iPhone, an entry is edited in its own form, and on iPad in the inspector, or in a sheet in a narrow window. The form also takes a duration, duplicates the entry and splits it.
- A start can't be after the end, nor the running timer's after now, and an end can't be before the start.
- The timeline shows a day or a week on an hour grid, or a month as a calendar. The grid opens at 7:00, or at the hour of an earlier entry on the days shown. Blocks show the project, times and note, and the tags when the block has room for them. On the Mac's grid, drag a block to move it, in the week view to another day too; drag its top or bottom edge to change its start or end; double-click empty space to add an hour. Click a day's heading in the week view, or double-click a day in the month view, to see it on its own.
- On iPad, tap a block to select it, which shows a handle on its top and bottom edges. Drag the selected block to move it, in the week view to another day too, or a handle to change its start or end; there's a tick for each five minutes. Only the selected block moves, so a swipe across the others scrolls. Double-tap empty space to add an hour, and tap a day's heading in the week view, or a day's number in the month view, to see it on its own.
- Right-clicking entries on the Mac, in the table or on the timeline, offers "Open #123 on GitHub" for tags that refer to issues, "Duplicate", "Split Entry…", the entry's overlap fixes, "Set Project…", "Add Tag", "Remove Tag" and "Delete". All but splitting and the overlap fixes work on every selected entry at once. Touching and holding an entry on iPad offers the same for that entry.
- "Duplicate" puts a copy right after the entry, with the same project, tags, note and length, so it doesn't overlap the original. Copies of several entries keep their order and follow the last one. The running timer isn't copied. The copy is selected, ready to move.
- "Split Entry…" cuts an entry in two at a time inside it, suggesting the middle, on five minutes. Both parts keep the project, tags and note. Splitting the running timer stops the first part there and keeps the second running.

## Clients and projects

- In reports, a project without a client is listed under "No client".
- Pickers show "Acme › Website redesign"; a project without a client has no prefix.
- On the Mac and iPad, the sidebar lists each client with its projects under the screens, then the projects without a client and, if there are any, the entries without a project, "Unassigned". Archived clients and projects are folded away under "Archived". New Project… and New Client… ask for the name; they're in the menu at the bottom of the Mac's sidebar and at the top of the iPad's. Right-clicking a project on the Mac starts its timer.
- Each client and project has a page: its time this week, this month and in all, and each of its last twelve weeks. A project's page lists its tags, and has a button that starts its timer, or stops it while it runs; a client's page lists its projects with their time and adds new ones. The unassigned entries have a page like a project's. The settings of a client or project are in the inspector of its page, or in a sheet in a narrow iPad window, which stays closed until Settings in the toolbar opens it.
- Typing in a project picker narrows the list to projects whose client or project name has each word typed, ignoring case and accents: "web", "site" and "acme web" all find "Acme › Website redesign". Projects whose name starts with what's typed come first. On the Mac, the arrow keys move through the list, Return picks, and Escape clears the search or closes the list.
- Archiving a client hides it and its projects from pickers and the menu bar's "Switch to" list. Their history stays in reports.
- Deleting a client or project that has entries isn't possible; the app offers to archive it instead. A client has entries when any of its projects does. Deleting a client deletes its projects too.
- Another device may still log time to a project deleted here. An entry pointing at a deleted project shows that project as archived, and so does a project whose client was deleted.
- "Merge Into…" moves every entry of one project to another, or every project of one client to another, and deletes the first. It's for when two devices each added "Acme".
- Entries point at the project, not the client, so moving a project to another client moves its history too, including in past reports.
- A project's settings, in the inspector of its page on the Mac and iPad and in the project's form on iPhone, show its GitHub repositories and the calendar its events come from on this device, and on iPhone its tags.

## Tags

- Tags are free text on each entry. Extra spaces are trimmed, matching ignores case, and `;` is dropped, because it separates tags in the CSV.
- Each project has its own tags: the ones on its entries, and for entries without a project, theirs. Typing a tag suggests the entry's project's tags with their existing spelling, and "Add Tag" offers them. An entry moved to another project takes its tags along.
- On the Mac and iPad, a project's page lists its tags with their time and entries, the busiest first, and a bar for each. Tags that refer to issues are listed apart, by repository, numbered, with an arrow that opens the issue; a long list shows its busiest eight until asked for all. Selecting a tag shows its settings in the inspector, or in a sheet in a narrow iPad window.
- Renaming a tag changes it on that project's entries only, and renaming it to another of the project's tags merges the two. A tag can also be removed from the project's entries.
- Reports filter and group by tag name across projects.

## GitHub

- A project can have GitHub repositories, added as "owner/name" or by pasting an address, including clone addresses and GitHub Enterprise servers.
- A tag like `#123` refers to issue or pull request 123 in the project's first repository. `api#123` refers to #123 in the project's repository named `api`, and `owner/repo#123` to #123 in any repository, as GitHub writes references. A slash before the "#" reads the same, so `api/#123` and `owner/repo/#123` work too. Any other tag is a plain tag.
- The first repository is marked "#123". To make another one the first, right-click it on the Mac, or swipe right on it or touch and hold it on iOS.
- Changing the repositories never moves a tag to another issue. When a tag would point elsewhere, because another repository became the first or the one it names was removed, it's rewritten to name the repository it meant: `#123` becomes `web#123`, or `acme/web#123` once `web` is removed, which still opens it. A tag written with a slash keeps it: `web/#123` becomes `acme/web/#123`. Where two repositories share a name, the owner is added too. The change and the rewritten tags are one step to undo. Removing a project's last repository leaves its tags as they are, so tags can wait for the right repository after a mistyped one.
- Tags that refer to issues are tinted. Clicking one in the menu bar, in the timeline's inspector, in a project's or tag's settings, or on iOS opens it in the browser. Right-clicking an entry offers "Open #123 on GitHub". The address is the issue's, which GitHub opens as the pull request when the number is one.
- The app doesn't talk to GitHub itself, so it needs no account or token, and private repositories open with the browser's GitHub sign-in.

## Time zones

- Each entry keeps the time zone it was recorded in. It's shown and edited in that zone, with a label such as "EDT" where that isn't the device's current zone.
- An entry belongs to the day it started on, in its own zone. Reports cover calendar days: an entry is in range when its day is.
- An entry that runs past midnight counts in full on its first day, in totals and the chart alike, so the chart adds up to the total.
- The timeline draws each entry at its own wall-clock time. On a travel day blocks can look as if they overlap when they don't; overlap warnings use real time.

## Durations

- Durations under a day are written as a stopwatch writes them, such as 7:45, and from a day up with their units, such as 42 h 31 m or 574 h, so a week's or a project's total doesn't read as a time of day. Every screen follows this rule, and seconds are left out.
- A duration can be typed as 1:30, 1.5, 90m, 1h 30m or 1h30, or as the app writes it.

## Reports

- A report covers a day, a week, a month or a custom range; the iPhone offers the first three. Weeks start on the day chosen in Settings.
- Its figures are the total, the average day worked, which leaves out days without time, how many days had time, and the change from the period before: the day, week or month before, or as many days before a custom range, with the same filters. While a period is under way, its days so far are compared with as many days at the start of the period before, so a week on its Wednesday is held against Monday to Wednesday of the week before. A day's report shows its entries and when its first entry started and its last one ended instead of the average and the days.
- The chart has a column for each day, stacked by project, with each day's total over it and a dashed line at the average day worked. A range longer than a month has a column for each week, and one longer than about four months a column for each month.
- Groups: by client, with each client's projects under it, then "No client" and "Unassigned"; by project; or by tag, then "Untagged". A client with one project takes one line, such as "Acme › Website". Each line has its share of the total and a bar for it; a client with several projects has a bar in their colors. An entry with two tags counts in full under each, so tag totals can add up to more than the total.
- Filters for clients, projects and tags on the Mac and iPad.
- Every entry counts in full, so the total equals the sum of end minus start over the CSV's rows. Where entries overlap, that time counts twice, and the report says how much: the sum of the durations minus the length of their union, which stays right when three entries overlap.
- A running timer isn't in the totals or the CSV. Reports show it on its own line, such as "Running: 0:42, not included".
- While iCloud files are still downloading or a file can't be read, reports say their totals may be incomplete.

## CSV export

The CSV has the entries behind the report: the same range and filters, one row each, whatever the grouping. On the Mac and iPad, File › Export CSV… saves every entry the same way, from the first day to the last, and so does Settings › Export All Entries… on iPad.

```csv
date,start,end,hours,client,project,tags,note
2026-09-23,2026-09-23T09:15:00+02:00,2026-09-23T11:40:00+02:00,2.4167,Acme,Website redesign,design;client-call,"Wireframe review, round 2"
2026-09-23,2026-09-23T13:00:00+02:00,2026-09-23T14:30:00+02:00,1.5000,,Internal tooling,,Release script
```

- UTF-8 with a byte-order mark, which Excel needs to read accented characters. Lines end in CRLF, and fields with commas, quotes or line breaks are quoted.
- `date` is the entry's day in its own time zone. `start` and `end` are ISO 8601 with the entry's own offset.
- `hours` has four decimals, because spreadsheets can't add up the ISO times. The column adds up to within seconds of the report total.
- Tags are joined with `;`. A project without a client has an empty client cell; an unassigned entry has empty client and project cells.
- On the Mac the file is saved through the save dialog, which gives the sandboxed app access to the chosen file. On iPhone and iPad a report's CSV goes to the share sheet, and every entry's is saved through the iPad's document picker.

## CSV import

File › Import CSV… on the Mac and iPad, also in the Mac's Entries toolbar, and Settings › Import CSV… on iPhone and iPad add entries from a CSV file. A summary shows what the file adds before anything changes, and the whole import is one step to undo.

- The app's own CSV reads back as it was exported. Detailed exports from other time trackers work too: columns are found by their headings, such as `start`, `end`, `start date`, `start time`, `end date`, `end time`, `date`, `duration`, `hours`, `client`, `project`, `tags`, and `note` or `description`. Commas, semicolons and tabs all separate fields.
- Date-times with an offset keep their wall-clock time: an entry recorded in New York still shows at its New York time. Times without an offset are read in the device's time zone, and so are times in UTC, ending in Z, since they don't say where the work was done. An end time earlier than the start is on the next day, unless an end date says otherwise.
- Date-times can also be written in ISO 8601's compact form, as Timewarrior and calendars write them: 20260713T152036Z, with or without seconds, and with Z, an offset such as +0200, or no zone.
- Dates can be written 2026-09-23, 20260923, 23.09.2026, 09/23/2026 or 23/09/2026. With slashes, the day comes first if any date in the file needs it, as 23/09/2026 does.
- Rows with a day and a duration but no times are placed one after another from 9:00.
- Clients and projects are matched by name, ignoring case, and added when they're new. Tags are separated by `;` or `,` and take the spelling of existing tags.
- A row with the same start, end, project and note as an entry that's already there is skipped, so importing a file twice adds its entries once.
- Rows that can't be read are listed by line and left out; the rest can still be imported.

## Calendar import

Each project can have a calendar on each device, chosen in the project's settings on the Mac, iPhone and iPad; one calendar per client. File › Import Calendar Events… on the Mac and iPad, also in the Mac's Entries toolbar's Import menu, and Settings › Import Calendar Events… on iPhone and iPad then add the events of linked calendars as entries. A summary shows what the import adds before anything changes, and the whole import is one step to undo.

- The app reads the calendars the Mac, iPhone or iPad has: every account in Internet Accounts, such as iCloud, Google or Exchange, and calendars subscribed to by link. It reads only linked calendars, and only when importing or showing a project's settings.
- Links are kept on each device, because each device identifies calendars differently and may have other accounts. A link follows its calendar when the calendar's id changes, as after its account is removed and added back, by the calendar's title and account.
- The import takes the events that start on the days chosen, from the start of this week through today unless changed. Each becomes an entry for the calendar's project, with the event's title as the note and no tags, recorded in the device's time zone.
- Events that aren't time spent working are left out, and the summary counts them by reason: all-day events, cancelled events, declined invitations, events shown as free or out of office, events that take no time or last more than a day, and events that haven't ended yet.
- An imported entry's id comes from the event: its id on the calendar server and, for one occurrence of a repeating event, when that occurrence was first scheduled. Importing the same days again, or on another device, finds the entries already there. An entry with the same start, end, project and note also counts as already there.
- Editing an imported entry keeps it as edited. Deleting one, or undoing the import, keeps it deleted when importing again, unless the summary's switch asks to import deleted entries again.
- Exchange gives an event different ids on the Mac and on iOS, so an Exchange calendar is best linked on one device only.

## Undo

Every edit can be undone and redone from the Edit menu, with ⌘Z and ⇧⌘Z on an iPad with a keyboard, or by shaking an iPhone. An undo is saved and synced like any other edit.
