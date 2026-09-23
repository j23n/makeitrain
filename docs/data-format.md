# Data format

All data lives in plain JSON files that any text editor can open. Only the app is meant to write them, but it copes with files that were edited, broken or deleted by hand.

```
Time Tracker/             ← iCloud Drive, or the app's local folder
├── projects.json         clients and projects
└── entries/
    ├── 2026-08.json
    └── 2026-09.json      one file per month
```

In iCloud, the folder is the `Documents` folder of the app's container, which Finder shows under iCloud Drive as "Time Tracker". Locally, it's `Data` in the app's Application Support folder.

## Month files

Each file in `entries/` holds the entries that started in that month:

```json
{
  "entries": [
    {
      "end": "2026-09-23T11:40:00+02:00",
      "endUpdated": "2026-09-23T11:40:00.412+02:00",
      "id": "2F6A1C9E-3B8D-4E5F-9A01-7C2D4B6E8F10",
      "note": "Wireframe review",
      "project": "8B41D7A0-5C2E-4F13-B6A9-0D7E3C1F2A54",
      "start": "2026-09-23T09:15:00+02:00",
      "tags": ["design", "client-call"],
      "timeZone": "Europe/Berlin",
      "updated": "2026-09-23T11:41:02.187+02:00"
    }
  ],
  "version": 1
}
```

| Field | Meaning |
| --- | --- |
| `id` | The entry's UUID. |
| `project` | The project's id. Missing for an unassigned entry, such as one started with just a note. |
| `start` | When the entry started, in whole seconds. |
| `end` | When it ended, in whole seconds. Missing while the timer runs. |
| `endUpdated` | When `end` was last set or cleared. `end` merges on this stamp, separately from the other fields. |
| `timeZone` | The zone the entry was recorded in, such as `Europe/Berlin`. |
| `tags` | Tag names. They never contain `;`. |
| `note` | Free text. |
| `updated` | When anything except `end` last changed, to the millisecond. |
| `deleted` | When the entry was deleted. |

An entry belongs to the month and the day of its start, in its own time zone, so every device files it the same way. When an edit moves the start into another month, the entry moves to that month's file.

## projects.json

```json
{
  "clients": [
    {
      "archived": false,
      "id": "5E0C9A2B-7F41-4D38-8B6E-1A2C3D4E5F60",
      "name": "Acme",
      "updated": "2026-09-01T07:00:00Z"
    }
  ],
  "projects": [
    {
      "archived": false,
      "client": "5E0C9A2B-7F41-4D38-8B6E-1A2C3D4E5F60",
      "color": "#4F7CAC",
      "id": "8B41D7A0-5C2E-4F13-B6A9-0D7E3C1F2A54",
      "name": "Website redesign",
      "updated": "2026-09-01T07:00:00Z"
    }
  ],
  "version": 1
}
```

A project without `client` belongs to no client. `color` is a hex color. Both kinds of record have `updated` and, once deleted, `deleted`.

## Times

- Entry times are ISO 8601 date-times with the offset of the entry's own time zone at that moment, such as `2026-09-23T09:15:00+02:00`. Reports therefore put entries on the right day even after travel.
- Client and project stamps are in UTC.
- Milliseconds appear only when they aren't zero. `start` and `end` never have them.
- In memory, times are whole milliseconds since 1970 (`Timestamp`), so every device compares them exactly.

## How files are written

The app writes JSON with its own small writer: keys sorted, two-space indents, short lists on one line, a newline at the end, and records in a fixed order (entries by start, clients and projects by name). The same data always produces the same bytes, whatever the OS version.

## Versions

Every file has a `version`. This app writes and reads version 1.

- A file with a newer version is never written; the app says the file needs a newer version of the app.
- Decoding ignores fields it doesn't know. Adding a field therefore needs a new version, or an older copy of the app would drop the field when it saves.

## Deletes

A deleted record keeps its place in the file with a `deleted` stamp, so merging with an older copy can't bring it back.

- A deleted entry loses its note and tags, so deleting it removes that text from the files.
- Deleted clients and projects keep their name, color and client, because entries on another device may still point at them. Such entries show the project as archived.

## Files edited by hand

- A file that isn't valid JSON, or doesn't have the expected shape, is never overwritten. The app names it in a notice, keeps working with everything else, and saves changes to that month once the file can be read again.
- iCloud sometimes keeps two files with the same name by numbering one, such as `2026-10 2.json` or `projects 2.json`. The app reads these too, merges them into the main file, and deletes them once that file is written.
- Other files in the folder are ignored.
