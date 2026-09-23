import Foundation
import Testing
@testable import TrackerCore

@Suite struct FileFormatTests {
    @Test func writesEntriesAsThePlanShows() {
        let entry = TimeEntry(
            id: UUID(uuidString: "2F6A1C9E-0000-4000-8000-000000000001")!,
            projectID: UUID(uuidString: "8B41D7A0-0000-4000-8000-000000000002")!,
            start: t("2026-09-23T09:15:00+02:00"),
            end: t("2026-09-23T11:40:00+02:00"),
            endUpdated: t("2026-09-23T11:40:00.412+02:00"),
            timeZone: "Europe/Berlin",
            tags: ["design", "client-call"],
            note: "Wireframe review",
            updated: t("2026-09-23T11:41:02.187+02:00")
        )
        let text = String(decoding: FileFormat.encode(entries: [entry]), as: UTF8.self)
        #expect(text == """
        {
          "entries": [
            {
              "end": "2026-09-23T11:40:00+02:00",
              "endUpdated": "2026-09-23T11:40:00.412+02:00",
              "id": "2F6A1C9E-0000-4000-8000-000000000001",
              "note": "Wireframe review",
              "project": "8B41D7A0-0000-4000-8000-000000000002",
              "start": "2026-09-23T09:15:00+02:00",
              "tags": ["design", "client-call"],
              "timeZone": "Europe/Berlin",
              "updated": "2026-09-23T11:41:02.187+02:00"
            }
          ],
          "version": 1
        }

        """)
    }

    @Test func writesProjectsWithUTCStamps() {
        let client = Client(id: uuid(1), name: "Acme", updated: t("2026-09-23T09:00:00+02:00"))
        let project = Project(id: uuid(2), clientID: uuid(1), name: "Website redesign", updated: t("2026-09-23T09:00:00.5Z"))
        let text = String(decoding: FileFormat.encode(clients: [client], projects: [project]), as: UTF8.self)
        #expect(text == """
        {
          "clients": [
            {
              "archived": false,
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Acme",
              "updated": "2026-09-23T07:00:00Z"
            }
          ],
          "projects": [
            {
              "archived": false,
              "client": "00000000-0000-0000-0000-000000000001",
              "color": "#4F7CAC",
              "id": "00000000-0000-0000-0000-000000000002",
              "name": "Website redesign",
              "updated": "2026-09-23T09:00:00.500Z"
            }
          ],
          "version": 1
        }

        """)
    }

    @Test func writesEmptyFilesCompactly() {
        let text = String(decoding: FileFormat.encode(entries: []), as: UTF8.self)
        #expect(text == "{\n  \"entries\": [],\n  \"version\": 1\n}\n")
    }

    @Test func sortsRecordsSoTheSameDataGivesTheSameFile() {
        let early = TimeEntry(id: uuid(2), start: t("2026-09-23T09:00:00Z"), timeZone: "UTC", updated: t("2026-09-23T09:00:00Z"))
        let late = TimeEntry(id: uuid(1), start: t("2026-09-23T10:00:00Z"), timeZone: "UTC", updated: t("2026-09-23T10:00:00Z"))
        #expect(FileFormat.encode(entries: [late, early]) == FileFormat.encode(entries: [early, late]))
    }

    @Test func readsWhatItWrites() throws {
        var rng = SeededGenerator(seed: 3)
        let characters: [Character] = [
            "a", "Z", " ", "\"", "\\", "/", "\n", "\t", "\u{0}", "\u{1F}", "\u{7F}", "é", "e\u{301}", "😀", "\u{2028}", ";", ",",
        ]
        for _ in 0..<300 {
            let text = String((0..<Int.random(in: 0...12, using: &rng)).map { _ in characters.randomElement(using: &rng)! })
            let entry = TimeEntry(
                id: randomUUID(using: &rng),
                projectID: Bool.random(using: &rng) ? randomUUID(using: &rng) : nil,
                start: t("2026-09-23T07:15:00Z"),
                end: Bool.random(using: &rng) ? t("2026-09-23T08:00:00Z") : nil,
                timeZone: ["Europe/Berlin", "America/New_York", "UTC"].randomElement(using: &rng)!,
                tags: [text, "x"],
                note: text,
                updated: t("2026-09-23T08:00:00.001Z"),
                deleted: Bool.random(using: &rng) ? t("2026-09-23T08:00:00.001Z") : nil
            )
            #expect(try FileFormat.decodeEntries(from: FileFormat.encode(entries: [entry])) == [entry])

            let client = Client(id: randomUUID(using: &rng), name: text, archived: Bool.random(using: &rng), updated: t("2026-09-23T08:00:00Z"))
            let project = Project(id: randomUUID(using: &rng), clientID: client.id, name: text, color: "#FFFFFF", updated: t("2026-09-23T08:00:00Z"))
            let decoded = try FileFormat.decodeProjects(from: FileFormat.encode(clients: [client], projects: [project]))
            #expect(decoded.clients == [client])
            #expect(decoded.projects == [project])
        }
    }

    @Test func fillsInMissingOptionalFields() throws {
        let json = """
        {"version": 1, "entries": [{"id": "2F6A1C9E-0000-4000-8000-000000000001",
          "start": "2026-09-23T09:15:00+02:00", "end": "2026-09-23T10:00:00+02:00",
          "timeZone": "Europe/Berlin", "updated": "2026-09-23T10:00:00+02:00", "somethingElse": 42}]}
        """
        let entry = try #require(try FileFormat.decodeEntries(from: Data(json.utf8)).first)
        #expect(entry.tags == [])
        #expect(entry.note == "")
        #expect(entry.projectID == nil)
        #expect(entry.endUpdated == entry.updated)
        #expect(try FileFormat.decodeProjects(from: Data(#"{"version": 1}"#.utf8)).clients == [])
    }

    @Test func refusesFilesFromANewerVersion() {
        let json = #"{"version": 2, "entries": [{"id": 1}], "somethingNew": true}"#
        #expect(problem(decoding: json) == .newerVersion(2))
    }

    @Test(arguments: [
        "",
        "not json",
        "[]",
        #"{"entries": []}"#,
        #"{"version": 0, "entries": []}"#,
        #"{"version": "1", "entries": []}"#,
        #"{"version": 1, "entries": [{"id": "not a uuid"}]}"#,
        #"{"version": 1, "entries": [{"id": "2F6A1C9E-0000-4000-8000-000000000001", "start": "yesterday", "timeZone": "UTC", "updated": "2026-09-23T10:00:00Z"}]}"#,
        #"{"version": 1, "entries": [{"id": "2F6A1C9E-0000-4000-8000-000000000001", "start": "2026-09-23T10:00:00Z", "updated": "2026-09-23T10:00:00Z"}]}"#,
    ])
    func refusesUnreadableFiles(json: String) {
        guard case .unreadable(let message)? = problem(decoding: json) else {
            Issue.record("Expected an unreadable file")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test func explainsWhatsWrong() {
        let json = #"{"version": 1, "entries": [{"id": "2F6A1C9E-0000-4000-8000-000000000001", "start": "2026-09-23T10:00:00Z", "updated": "2026-09-23T10:00:00Z"}]}"#
        #expect(problem(decoding: json) == .unreadable(#"Missing "timeZone" at entries.[0]"#))
    }

    private func problem(decoding json: String) -> FileProblem? {
        do {
            _ = try FileFormat.decodeEntries(from: Data(json.utf8))
            return nil
        } catch {
            return error as? FileProblem
        }
    }
}
