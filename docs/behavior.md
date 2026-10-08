# Behavior

The rules the app follows, whichever screen or device an edit comes from. One timer runs at a time, time is started, switched, stopped and logged by typing a line, entries may overlap but are flagged, and what needs correcting is shown in place until you accept a fix.

## The command line

The command line is how time gets in. It's in the Mac's menu bar popover, in the panel a global shortcut opens over any app, and in the bar at the top of the Mac's main window, where ⌘K puts the keyboard in it. On iPhone it floats over the tab bar and opens over the screen when tapped; an iPad window that's wide enough has it in the bar at the top, as on the Mac.

What a line can say:

| Line | What it does |
| --- | --- |
| `web #12 Fix login` | Starts a timer for Website with the tag #12 and a note, or switches to it |
| `web #12` | The same, with the note of the last entry tagged #12 |
| `brand from 11:05`, `brand -15m` | Switches, starting at 11:05 or 15 minutes ago |
| `from 10:30` | Changes the running timer's start to 10:30 |
| `stop`, `stop 11:05`, `stop -10m` | Stops the timer now, or earlier |
| `web review 9:00-10:30` | Logs a finished entry; also `9-10:30`, `9am-11am` and `9:00 to 17:00` |
| `web review wed 14-16` | On another day: `yesterday`, `wed`, `30 sep`, `sep 30` or `2026-09-30` |
| `web review for 45m` | Logs 45 minutes ending now |
| `new project App for acme` | Adds a project, and its client if it's new |
| `new client Acme` | Adds a client |
| `archive brand`, `unarchive brand` | Archives a project or client, or brings it back |
| `color web teal` | Blue, red, green, purple, orange, teal, gold or gray, or a hex color |
| `rename web to Website v2` | Renames a project or client |
| `merge acme2 into acme` | Moves everything to the second, then deletes the first |
| `find export pdf` | Lists the entries with those words |

- In a sidebar on the Mac and a wide iPad window, and under the line on iPhone and in the menu bar, the app says what Return would do and what that changes, before anything does: "Switch to Brand refresh, logo review. Website ends at 10:40, after 1:10. No gap, no overlap." A change that would make an overlap says so. A line that can't be done says why, such as a start after the running timer's or an end in the future. The sidebar has buttons for Return and for Option-Return, and while it shows, it takes the place of the screen's own panel, such as the week's corrections or the month's statement.
- Option-Return does what the line could also mean: for a timer, log it as done instead, from when the last entry today ended to now; for a new project, add it and start a timer for it. On iPhone it's a second button.
- While a word is typed, what could take its place shows in the sidebar, or under the line: projects whose name or client's name has a word starting with it, where the line's project goes; the project's tags after `#`, or every project's without one; the starts and ends of the day's other entries, and now, where a time goes, as after `from` or in `9:00-1`; and at the start, commands such as `stop` and `new project`, and after one, what it acts on. Tab takes the highlighted one, Up and Down move the highlight, and a click takes any. The word can be anywhere in the line.
- Otherwise Tab finishes the line from the last entry like it, as "web #12 Fix login, from Wed", and Up and Down bring back earlier lines, which get no suggestions until they're changed; Down on an empty line lists today's entries, and clicking a found or listed entry shows it on its week. The suggestions, the lines run lately and the words to add, such as `from 10:30`, `−15m` and `#`, are buttons in the sidebar, and under the line on iPhone.
- The words are colored as they're read: a project underlined in its color, a client underlined, tags in blue, times in amber, words such as `stop` and `new project` in the accent color, a new name in bold, and a name that matches nothing dotted underneath.
- A project is found by the start of its words or its client's: `web`, `acme web` and `ac we` all find Acme's Website, ignoring case and accents. When two match as well, the one used last wins. Short words such as "a", "the", "for" and "with" don't match a project on their own, so they stay part of the note.
- A time typed without a day is today's, or yesterday's when today's hasn't come yet and yesterday's was in the last 12 hours, as when typing `from 23:30` just after midnight. A day counts only next to a time. An end hour below the start, as in `9-5`, is in the afternoon.
- Tags are written with a `#` or as the project already has them. A tag typed in another case takes the project's spelling. `#daily` loses its `#`, unless the project has it with one; references such as `#227` and `api#12` keep it.
- After a line runs, the popover and the shortcut's panel close, unless Settings says to keep them open. Every line run is remembered on that device, the latest 100.

## Timer

- Starting a timer stops the running one at the same instant, so switching tasks leaves no gap and no overlap.
- A timer needs no project: a note or tags will do. The entry shows as "Unassigned", with an empty ring where a project's color would be, until it gets one.
- The menu bar shows the running timer's hours and minutes, and the project's name if Settings says so, and marks the icon when something needs correcting, which Settings can turn off.
- On iPhone, the running timer is a Live Activity on the Lock Screen and in the Dynamic Island while Settings allows it, counting up, with a Stop button. Control Center, the Lock Screen and the Action button can have a control that opens the command line and one that stops the timer, on iOS 18. Siri and the Shortcuts app can start a timer from what you say, as on the command line, stop it, and open the command line.
- A stopped entry never runs again; continuing work starts a new entry. That's what lets a stop win over edits made to an out-of-date copy on another device. Undoing a stop is the one exception: it resumes the timer.
- Start and end times are whole seconds. Dragging on the week snaps them to five minutes.
- There's no idle detection. A timer left running is found as a correction instead.

## Corrections

What needs correcting is found when the days are shown and never stored:

- **Overlaps:** two entries both count the same time.
- **Timers that ran long:** an entry over 12 hours, or one that ran past midnight into 5:00 or later.
- **Entries without a project.**
- **Calendar events not logged:** events of a project's calendar that no entry covers. An event counts as logged when at least half of it is logged to its project.

On the Mac's and the iPad's week, each correction is numbered and listed in the sidebar while there are any, and drawn in place: the times a fix would change struck through with the new ones beside them, entries a fix would add as dashed outlines, time counted twice hatched, and the end a long timer likely had as a line. On iPhone, the week's corrections are a panel at the bottom, one at a time, and Today says how many there are.

- Each correction offers its fixes, the likeliest first, and nothing changes until one is chosen. Return accepts the selected one's first fix, J and K move between them, and Tab skips one. A skipped correction isn't offered again on that device.
- **Overlaps:** trim the earlier entry to end where the later starts, trim the later to start where the earlier ends, or, when one contains the other, split the outer one around the inner. Entries that start together offer to trim the longer. Dragging the seam between them moves the end of one and the start of the other together.
- **Long timers:** end at the usual end of the day, or an hour before or after. The usual end is the middle of the last ends of the four weeks before, leaving out entries that ran long, or 18:00 with nothing to go by, on five minutes.
- **No project:** the project of another entry with the same note, when there is one, or a project to choose.
- **Calendar events:** log the event as an entry for its project, with its title as the note.
- "Accept all" applies every first fix, one after another, each against the result of the last, as one step to undo. The week's total is shown struck through next to what it would be with the fixes, and so is each day's.

## Overlaps

- Overlaps are worked out when the data is displayed. Entries are scanned in order of start while tracking the latest end so far, and an entry overlaps if it starts before that end. That also catches an entry that overlaps an earlier, longer one with a shorter entry in between.
- A running timer counts as ending now. Deleted entries and entries with no duration are ignored.
- Reports count the time twice and say how much: the sum of the durations minus the length of their union, which stays right when three entries overlap. The month marks the days they're on.

## Editing entries

- The week, or a day, shows entries as blocks on an hour grid, from 7:00 to 19:00, widened to any entry and to the time now. Blocks show their times, title and tags in the project's color. A day with nothing on a weekend is left out of the week.
- On the Mac and a wide iPad window, drag a block to move it, to another day too, or its top or bottom edge to change its start or end. Clicking an entry shows it in the sidebar, in place of the corrections, as the iPhone's entry sheet does: its line, such as `2 oct 13:30-16:30 web #12 Fix login`, to change by typing, what the line reads as (its day, times and length, project, tags and note, or why it isn't an entry), and Stop or Continue it now, Duplicate, Split in the middle and Delete. Return puts the keyboard in the line and applies it; Escape puts it back, and closes the entry when it's unchanged. While the line is edited, the same suggestions show under it. A line without times, such as `web Fix login`, keeps the entry's.
- On iPhone, tap an entry to change it as a line, or to stop, continue, duplicate, split or delete it. Touching and holding an entry, or right-clicking one on the Mac, offers the same, and setting its project.
- "Duplicate" puts a copy right after the entry, with the same project, tags, note and length, so it doesn't overlap the original. The running timer isn't copied.
- "Split" cuts an entry in two in the middle, on five minutes. Both parts keep the project, tags and note. Splitting the running timer stops the first part there and keeps the second running.
- A start can't be after the end, nor the running timer's after now, and an end can't be before the start or in the future.

## Month, year and reports

- The month shows its days with each one's time as a bar by project and a mark where entries overlap, the year's weeks above them, and the statement beside them. Clicking a day shows it alone; Shift-clicking, or Shift and the arrows, stretches the range; Return opens the day and W its week. On iPhone, tap a day to show it alone, and hold and drag across days for a range. The year shows its weeks and a small month for each month.
- What a report covers reads as a sentence of choices, "Acme in September 2026 by tag", and can be typed: ⌘L on the Mac, and the command line on iPhone's Month. A typed report takes clients, projects and tags by name; a period such as `today`, `yesterday`, `this week`, `last month`, `sep`, `sep 2026`, `sep-oct`, `1-15 sep`, `q3`, `2026`, `ytd` or `2026-09-01 to 2026-09-15`; and `by client`, `by project` or `by tag`. A month without a year is the last one up to today. Words it doesn't know are marked and left out.
- The statement has the figures: the total, the average day worked, which leaves out days without time, how many days had time out of the weekdays, and the change from the period before, with the same filters. While a period is under way, its days so far are compared with as many days at the start of the period before. Then the time by client, project or tag, with each line's share; tags that refer to issues link to them.
- Before sending, the statement shows time counted twice and on which days, with a link to fix them in the week, whether a timer is running, which isn't included until it stops, and whether all data is downloaded.
- Groups: by client, with each client's projects under it, then "No client" and "Unassigned"; by project; or by tag, then "Untagged". An entry with two tags counts in full under each, so tag totals can add up to more than the total.
- Every entry counts in full, so the total equals the sum of end minus start over the CSV's rows. A running timer isn't in the totals or the CSV.
- Save CSV… (⌘E) saves the report's entries; Save PDF… (⌘P) saves a statement to send, on A4 pages: who and when, the total, the time by project or by tag, and every entry.
- Weeks start on the day chosen in Settings.

## CSV export

The CSV has the entries behind the report: the same range and filters, one row each, whatever the grouping. On the Mac, File › Export CSV… saves every entry the same way, from the first day to the last, and so does Settings › Export All Entries… on iPhone and iPad.

```csv
date,start,end,hours,client,project,tags,note
2026-09-23,2026-09-23T09:15:00+02:00,2026-09-23T11:40:00+02:00,2.4167,Acme,Website redesign,design;client-call,"Wireframe review, round 2"
2026-09-23,2026-09-23T13:00:00+02:00,2026-09-23T14:30:00+02:00,1.5000,,Internal tooling,,Release script
```

- UTF-8 with a byte-order mark, which Excel needs to read accented characters. Lines end in CRLF, and fields with commas, quotes or line breaks are quoted.
- `date` is the entry's day in its own time zone. `start` and `end` are ISO 8601 with the entry's own offset.
- `hours` has four decimals, because spreadsheets can't add up the ISO times. The column adds up to within seconds of the report total.
- Tags are joined with `;`. A project without a client has an empty client cell; an unassigned entry has empty client and project cells.
- On the Mac the file is saved through the save dialog, which gives the sandboxed app access to the chosen file; on iPhone and iPad, through the document picker.

## Clients and projects

- The projects list has each client with its projects, then the projects without a client and the entries without a project, "Unassigned". Each project shows its GitHub repositories, its calendar on this device, its time this week and this month, a bar for each of its last twelve weeks, and its total time. Archived clients and projects are folded away. On the Mac, the arrows move, Return opens a project's page, and R, C, A, M and N rename, color, archive, merge or add, by putting the line for it in the command line.
- A project's page has its time this week, this month and in total, its last twelve weeks day by day, with days over 12 hours in amber, and its tags with their time, those that refer to issues grouped by repository. Selecting a tag renames it, merges it into another or removes it. Its settings are beside it on the Mac and a wide iPad window, and behind Edit on iPhone: its name, client, color, GitHub repositories, the calendar on this device, and archiving, merging or deleting it.
- Pickers show "Acme › Website redesign"; a project without a client has no prefix.
- Archiving a client hides it and its projects from pickers and the command line. Their history stays in reports.
- A project that has entries can't be deleted; archive it instead. A client can be archived, or merged into another, but not deleted.
- Another device may still log time to a project deleted here. An entry pointing at a deleted project shows that project as archived, and so does a project whose client was deleted.
- Merging moves every entry of one project to another, or every project of one client to another, and deletes the first. It's for when two devices each added "Acme".
- Entries point at the project, not the client, so moving a project to another client moves its history too, including in past reports.

## Tags

- Tags are free text on each entry. Extra spaces are trimmed, matching ignores case, and `;` is dropped, because it separates tags in the CSV.
- Each project has its own tags: the ones on its entries, and for entries without a project, theirs. A tag typed in another case takes the spelling the project has. An entry moved to another project takes its tags along.
- Renaming a tag changes it on that project's entries only, and renaming it to another of the project's tags merges the two. A tag can also be removed from the project's entries.
- Reports filter and group by tag name across projects.

## GitHub

- A project can have GitHub repositories, added as "owner/name" or by pasting an address, including clone addresses and GitHub Enterprise servers.
- A tag like `#123` refers to issue or pull request 123 in the project's first repository. `api#123` refers to #123 in the project's repository named `api`, and `owner/repo#123` to #123 in any repository, as GitHub writes references. A slash before the "#" reads the same, so `api/#123` and `owner/repo/#123` work too. Any other tag is a plain tag.
- The first repository is marked "#123"; "Make first" makes another one the first.
- Changing the repositories never moves a tag to another issue. When a tag would point elsewhere, because another repository became the first or the one it names was removed, it's rewritten to name the repository it meant: `#123` becomes `web#123`, or `acme/web#123` once `web` is removed, which still opens it. A tag written with a slash keeps it: `web/#123` becomes `acme/web/#123`. Where two repositories share a name, the owner is added too. The change and the rewritten tags are one step to undo. Removing a project's last repository leaves its tags as they are, so tags can wait for the right repository after a mistyped one.
- Tags that refer to issues are tinted and open the issue in the browser, from a project's page and from reports. The address is the issue's, which GitHub opens as the pull request when the number is one.
- The app doesn't talk to GitHub itself, so it needs no account or token, and private repositories open with the browser's GitHub sign-in.

## Time zones

- Each entry keeps the time zone it was recorded in. It's shown and edited in that zone.
- An entry belongs to the day it started on, in its own zone. Reports cover calendar days: an entry is in range when its day is.
- An entry that runs past midnight counts in full on its first day, and the next day shows where it ended, as "–08:55 Thursday's Refactoring".
- The week draws each entry at its own wall-clock time. On a travel day blocks can look as if they overlap when they don't; overlap warnings use real time.

## Durations

- Durations under a day are written as a stopwatch writes them, such as 7:45, and from a day up with their units, such as 42 h 31 m or 574 h, so a week's or a project's total doesn't read as a time of day. Every screen follows this rule, and seconds are left out. Digits keep an even width, so columns of times line up.
- A duration can be typed as 45m, 1h30, 1h 30m or 90 min, and 1:30 or 1.5 where a duration is expected.

## CSV import

File › Import CSV… on the Mac, and Settings › Import CSV… on the Mac, iPhone and iPad add entries from a CSV file. A summary shows what the file adds before anything changes, and the whole import is one step to undo.

- The app's own CSV reads back as it was exported. Detailed exports from other time trackers work too: columns are found by their headings, such as `start`, `end`, `start date`, `start time`, `end date`, `end time`, `date`, `duration`, `hours`, `client`, `project`, `tags`, and `note` or `description`. Commas, semicolons and tabs all separate fields.
- Date-times with an offset keep their wall-clock time: an entry recorded in New York still shows at its New York time. Times without an offset are read in the device's time zone, and so are times in UTC, ending in Z, since they don't say where the work was done. An end time earlier than the start is on the next day, unless an end date says otherwise.
- Date-times can also be written in ISO 8601's compact form, as Timewarrior and calendars write them: 20260713T152036Z, with or without seconds, and with Z, an offset such as +0200, or no zone.
- Dates can be written 2026-09-23, 20260923, 23.09.2026, 09/23/2026 or 23/09/2026. With slashes, the day comes first if any date in the file needs it, as 23/09/2026 does.
- Rows with a day and a duration but no times are placed one after another from 9:00.
- Clients and projects are matched by name, ignoring case, and added when they're new. Tags are separated by `;` or `,` and take the spelling of existing tags.
- A row with the same start, end, project and note as an entry that's already there is skipped, so importing a file twice adds its entries once.
- Rows that can't be read are listed by line and left out; the rest can still be imported.

## Calendars

Each project can have a calendar on each device, chosen in the project's settings or in Settings. A project has one calendar at most, and a calendar belongs to one project. Its events that aren't logged show up in the week as corrections, to log one by one or all at once. File › Import Calendar Events… on the Mac and Settings › Import Calendar Events… on the Mac, iPhone and iPad add the events of some days in one go. A summary shows what the import adds before anything changes, and the whole import is one step to undo.

- The app reads the calendars the device has: every account in Internet Accounts, such as iCloud, Google or Exchange, and calendars subscribed to by link. It reads only linked calendars, and only when showing days or importing.
- Links are kept on each device, because each device identifies calendars differently and may have other accounts. A link follows its calendar when the calendar's id changes, as after its account is removed and added back, by the calendar's title and account.
- Each event becomes an entry for the calendar's project, with the event's title as the note and no tags, recorded in the device's time zone. The import takes the events that start on the days chosen, from the start of this week through today unless changed.
- Events that aren't time spent working are left out, and the import's summary counts them by reason: all-day events, cancelled events, declined invitations, events shown as free or out of office, events that take no time or last more than a day, and events that haven't ended yet.
- An imported entry's id comes from the event: its id on the calendar server and, for one occurrence of a repeating event, when that occurrence was first scheduled. Importing the same days again, or on another device, finds the entries already there. An entry with the same start, end, project and note also counts as already there.
- Editing an imported entry keeps it as edited. Deleting one, or undoing the import, keeps it deleted when importing again, unless the summary's switch asks to import deleted entries again.
- Exchange gives an event different ids on the Mac and on iOS, so an Exchange calendar is best linked on one device only.

## Settings

- **Appearance:** light, dark, or following the system, on each device.
- **On the Mac:** opening at login, the first day of the week, the shortcut that opens the command line over any app (none until you set one), whether the command line closes after Return, a list of commands, and what the menu bar shows.
- **On iPhone and iPad:** the Live Activity, how to add the controls and shortcuts, and the first day of the week.
- **Data:** where the data is and when it was saved, keeping it in iCloud Drive or on the device, the data files and whether each could be read, backups, and importing and exporting.
- **Calendars:** which calendar on this device belongs to which project.

These settings stay on the device. Clients, projects and entries are in the data files, and those sync.

## Undo

Every edit can be undone and redone from the Edit menu, with ⌘Z and ⇧⌘Z on an iPad with a keyboard, or by shaking an iPhone. A line run on the command line, an accepted correction and "Accept all" are each one step. An undo is saved and synced like any other edit.
