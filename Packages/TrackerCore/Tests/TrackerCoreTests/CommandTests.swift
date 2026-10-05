import Foundation
import Testing
@testable import TrackerCore

@Suite struct CommandTests {
    typealias F = CommandFixture

    func draft(_ projectID: UUID?, _ tags: [String] = [], _ note: String = "") -> EntryDraft {
        EntryDraft(projectID: projectID, tags: tags, note: note)
    }

    // MARK: - Starting and switching

    @Test func startsATimerForAProjectWithTagsAndANote() {
        let reading = F.read("book #227 Export to PDF")
        #expect(reading.primary == .start(draft(F.bookings, ["#227"], "Export to PDF"), at: F.at("10:40"), end: nil))
        #expect(reading.problem == nil)
        #expect(reading.tokens.map(\.kind) == [.project(F.bookings), .tag, .note, .note, .note])
        // Option-Return logs it as done since the last entry ended, at 09:00.
        #expect(reading.alternate == .start(draft(F.bookings, ["#227"], "Export to PDF"), at: F.at("09:00"), end: F.at("10:40")))
    }

    @Test func switchesFromTheRunningTimer() {
        let reading = F.read("harbor release call", F.ledger([F.runningBookings]))
        #expect(reading.primary == .start(draft(F.harbor, [], "release call"), at: F.at("10:40"), end: nil))
        #expect(reading.alternate == nil)
        #expect(reading.alternateProblem == .needsStart)
    }

    @Test func switchesAtAnEarlierTimeWithTheNoteOfTheTag() {
        let reading = F.read("book #227 from 11:05", F.ledger(F.switchedToHarbor), now: "12:20")
        #expect(reading.primary == .start(draft(F.bookings, ["#227"], "Export to PDF"), at: F.at("11:05"), end: nil))
        #expect(reading.noteFrom == uuid(103))
        #expect(reading.alternate == .start(draft(F.bookings, ["#227"], "Export to PDF"), at: F.at("11:05"), end: F.at("12:20")))
        #expect(reading.tokens.map(\.kind) == [.project(F.bookings), .tag, .time])
    }

    @Test func startingBeforeTheRunningTimerStartedIsAProblem() {
        let reading = F.read("book from 10:00", F.ledger(F.switchedToHarbor), now: "12:20")
        #expect(reading.primary == nil)
        #expect(reading.problem == .beforeRunningStart(F.at("10:40")))
    }

    @Test func whatsRunningAlreadyIsAProblem() {
        let reading = F.read("book #227", F.ledger([F.runningBookings]))
        #expect(reading.primary == nil)
        #expect(reading.problem == .runningAlready)
    }

    @Test func aTimeAloneMovesTheRunningTimersStart() {
        let ledger = F.ledger([F.runningBookings])
        #expect(F.read("from 9:00", ledger).primary == .moveStart(to: F.at("09:00")))
        #expect(F.read("-1h", ledger).primary == .moveStart(to: F.at("09:40")))
        // With nothing running, it starts an unassigned timer.
        #expect(F.read("from 10:00").primary == .start(draft(nil), at: F.at("10:00"), end: nil))
    }

    // MARK: - Times

    @Test func logsARange() {
        let reading = F.read("harbor retro 16:30-17:15", now: "18:00")
        #expect(reading.primary == .log(draft(F.harbor, [], "retro"), start: F.at("16:30"), end: F.at("17:15")))
        #expect(reading.alternate == nil)
    }

    @Test func readsTimesInManyForms() {
        func range(_ text: String) -> [Timestamp] {
            guard case let .log(_, start, end)? = F.read(text, now: "18:00").primary else { return [] }
            return [start, end]
        }
        #expect(range("book 9-10") == [F.at("09:00"), F.at("10:00")])
        #expect(range("book 9:00 - 9:30") == [F.at("09:00"), F.at("09:30")])
        #expect(range("book 9am-11am") == [F.at("09:00"), F.at("11:00")])
        #expect(range("book 11-1pm") == [F.at("11:00"), F.at("13:00")])
        #expect(range("book 13:30–17:45") == [F.at("13:30"), F.at("17:45")])
        #expect(range("book from 9 to 17:00") == [F.at("09:00"), F.at("17:00")])
        #expect(range("book review for 45m") == [F.at("17:15"), F.at("18:00")])
        #expect(range("book wed 9:00-9:30") == [F.at("09:00", on: "2026-09-30"), F.at("09:30", on: "2026-09-30")])
        #expect(range("book 30 sep 9-10") == [F.at("09:00", on: "2026-09-30"), F.at("10:00", on: "2026-09-30")])
        #expect(range("book 2026-09-30 9-10") == [F.at("09:00", on: "2026-09-30"), F.at("10:00", on: "2026-09-30")])
        #expect(range("book from 9:00 for 1h30") == [F.at("09:00"), F.at("10:30")])

        #expect(F.read("book -15m", now: "18:00").primary == .start(draft(F.bookings), at: F.at("17:45"), end: nil))
        #expect(F.read("book 15 min ago", now: "18:00").primary == .start(draft(F.bookings), at: F.at("17:45"), end: nil))
        // Plain numbers on either side of "to" are words of the note.
        #expect(F.read("book sprint 9 to 5", now: "18:00").primary == .start(draft(F.bookings, [], "sprint 9 to 5"), at: F.at("18:00"), end: nil))
    }

    @Test func aRangeAfterMidnightIsYesterdays() {
        let reading = F.read("book fix 22:00-23:30", now: "00:30", on: "2026-10-06")
        #expect(reading.primary == .log(draft(F.bookings, [], "fix"), start: F.at("22:00"), end: F.at("23:30")))
    }

    @Test func aDayWithoutATimeIsPartOfTheNote() {
        let reading = F.read("book review wed")
        #expect(reading.primary == .start(draft(F.bookings, [], "review wed"), at: F.at("10:40"), end: nil))
        #expect(reading.tokens.map(\.kind) == [.project(F.bookings), .note, .note])
    }

    @Test func timesLaterThanNowAreProblems() {
        #expect(F.read("book from 11:05").problem == .startsInFuture)
        #expect(F.read("book from 11:05").primary == nil)
        #expect(F.read("book 10:00-11:00").problem == .endsInFuture)
        #expect(F.read("book until 10:00").problem == .needsStart)
    }

    // MARK: - Stopping

    @Test func stops() {
        let ledger = F.ledger([F.runningBookings])
        #expect(F.read("stop", ledger).primary == .stop(at: F.at("10:40")))
        #expect(F.read("stop 10:15", ledger).primary == .stop(at: F.at("10:15")))
        #expect(F.read("stop -10m", ledger).primary == .stop(at: F.at("10:30")))
        #expect(F.read("stop 10 min ago", ledger).primary == .stop(at: F.at("10:30")))
        #expect(F.read("stop at 9:00", ledger).problem == .beforeRunningStart(F.at("09:30")))
        #expect(F.read("stop").problem == .notRunning)
        // "stop" followed by words that aren't a time is a note.
        #expect(F.read("stop button fix", ledger).primary == .start(draft(nil, [], "stop button fix"), at: F.at("10:40"), end: nil))
    }

    // MARK: - Projects and tags

    @Test func tagsAreSpelledAsTheProjectHasThem() {
        let reading = F.read("book #daily #standup api#12 Scheduler/#227,")
        #expect(reading.draft?.tags == ["Daily", "standup", "api#12", "Scheduler/#227"])
    }

    @Test func projectsMatchTheStartsOfTheirOrTheirClientsWords() {
        #expect(F.read("northbridge review").draft == draft(F.bookings, [], "review"))
        #expect(F.read("zen review").draft == draft(F.harbor, [], "review"))
        #expect(F.read("a quick fix").draft == draft(nil, [], "a quick fix"))
        // Archived projects aren't started.
        #expect(F.read("admin taxes").draft == draft(nil, [], "admin taxes"))
    }

    @Test func amongEqualMatchesTheProjectUsedLastWins() {
        let stamp = t("2026-06-01T09:00:00+02:00")
        let ledger = Ledger(
            clients: [Client(id: uuid(3), name: "Acme", updated: stamp), Client(id: uuid(4), name: "Globex", updated: stamp)],
            projects: [
                Project(id: uuid(15), clientID: uuid(3), name: "Website", updated: stamp),
                Project(id: uuid(16), clientID: uuid(4), name: "Webshop", updated: stamp),
            ],
            entries: [
                F.entry(110, uuid(15), "2026-09-01", "09:00", "10:00"),
                F.entry(111, uuid(16), "2026-09-15", "09:00", "10:00"),
            ]
        )
        #expect(F.read("web fix", ledger).draft?.projectID == uuid(16))
    }

    @Test func completesFromTheLastEntryThatHasWhatsTyped() {
        let completion = F.read("harbor").completion
        #expect(completion?.text == "harbor Check-in")
        #expect(completion?.entryID == uuid(102))
        #expect(completion?.day == LocalDate(year: 2026, month: 9, day: 30))
        #expect(F.read("harbor che").completion?.text == "harbor Check-in")
        #expect(F.read("harbor release").completion == nil)
        #expect(F.read("book #227").completion?.text == "book #227 Export to PDF")
    }

    // MARK: - Clients and projects

    @Test func addsProjectsAndClients() {
        let phoenix = F.read("new project Phoenix for zenith")
        #expect(phoenix.primary == .addProject(name: "Phoenix", client: .existing(F.zenith), color: "#8064A2", startsTimer: false))
        #expect(phoenix.alternate == .addProject(name: "Phoenix", client: .existing(F.zenith), color: "#8064A2", startsTimer: true))
        #expect(phoenix.tokens.map(\.kind) == [.keyword, .name, .keyword, .client(F.zenith)])
        #expect(F.read("new project Phoenix for Acme").primary == .addProject(name: "Phoenix", client: .new("Acme"), color: "#8064A2", startsTimer: false))
        #expect(F.read("new project Phoenix").primary == .addProject(name: "Phoenix", client: nil, color: "#8064A2", startsTimer: false))
        #expect(F.read("new project Harbor for zenith").problem == .nameTaken("Harbor"))
        #expect(F.read("new project").problem == .needsName)
        #expect(F.read("new client Acme").primary == .addClient(name: "Acme"))
        #expect(F.read("new client zenith").problem == .nameTaken("zenith"))
    }

    @Test func archives() {
        #expect(F.read("archive harbor").primary == .archive(.project(F.harbor), archived: true))
        #expect(F.read("archive zenith").primary == .archive(.client(F.zenith), archived: true))
        #expect(F.read("unarchive admin").primary == .archive(.project(F.admin), archived: false))
        #expect(F.read("archive nothing").problem == .notFound("nothing"))
        #expect(F.read("archive").problem == .needsName)
    }

    @Test func colors() {
        #expect(F.read("color book teal").primary == .setColor(project: F.bookings, color: "#4BACC6"))
        #expect(F.read("color book #123456").primary == .setColor(project: F.bookings, color: "#123456"))
        #expect(F.read("color book").problem == .needsColor)
        #expect(F.read("color book mauve").problem == .unknownColor("mauve"))
    }

    @Test func merges() {
        #expect(F.read("merge harbor into book").primary == .merge(.project(F.harbor), into: .project(F.bookings)))
        #expect(F.read("merge zenith into northbridge").primary == .merge(.client(F.zenith), into: .client(F.northbridge)))
        #expect(F.read("merge harbor into zenith").problem == .mixedTargets)
        #expect(F.read("merge harbor").problem == .needsTarget)
        #expect(F.read("merge book into book").problem == .sameTarget)
    }

    @Test func renames() {
        #expect(F.read("rename book to Bookings Pro").primary == .rename(.project(F.bookings), to: "Bookings Pro"))
        #expect(F.read("rename zenith to Zenith GmbH").primary == .rename(.client(F.zenith), to: "Zenith GmbH"))
        #expect(F.read("rename book to").problem == .needsName)
    }

    @Test func finds() {
        #expect(F.read("find export pdf").primary == .find("export pdf"))
        #expect(F.read("find").primary == nil)
    }
}

@Suite struct TimeWordTests {
    @Test func readsTimesOfDay() {
        #expect(TimeWords.clock("9") == TimeWords.Clock(second: 32400, bare: true, meridiem: false))
        #expect(TimeWords.clock("09:30")?.second == 34200)
        #expect(TimeWords.clock("9:30am")?.second == 34200)
        #expect(TimeWords.clock("9:30PM")?.second == 77400)
        #expect(TimeWords.clock("12am")?.second == 0)
        #expect(TimeWords.clock("12pm")?.second == 43200)
        #expect(TimeWords.clock("24:00")?.second == 86400)
        for text in ["25", "9:60", "930", "9:5", "13pm", "", "am", "9-10"] {
            #expect(TimeWords.clock(text) == nil, "\(text)")
        }
    }

    @Test func readsDurationsThatSayTheirUnit() {
        let minute: Int64 = 60000
        #expect(Durations.parseWithUnit("45m") == 45 * minute)
        #expect(Durations.parseWithUnit("45min") == 45 * minute)
        #expect(Durations.parseWithUnit("1h") == 60 * minute)
        #expect(Durations.parseWithUnit("2hrs") == 120 * minute)
        #expect(Durations.parseWithUnit("1h30") == 90 * minute)
        #expect(Durations.parseWithUnit("1.5h") == 90 * minute)
        for text in ["90", "1:30", "9am", "m", "0m"] {
            #expect(Durations.parseWithUnit(text) == nil, "\(text)")
        }
        #expect(TimeWords.ago("-15m") == 15 * minute)
        #expect(TimeWords.ago("−1h30") == 90 * minute)
        #expect(TimeWords.ago("-1:30") == 90 * minute)
        #expect(TimeWords.ago("15m") == nil)
    }

    @Test func readsDays() {
        let today = LocalDate(year: 2026, month: 10, day: 5)
        #expect(TimeWords.day("today", today: today) == today)
        #expect(TimeWords.day("Yesterday", today: today) == LocalDate(year: 2026, month: 10, day: 4))
        #expect(TimeWords.day("mon", today: today) == today)
        #expect(TimeWords.day("wednesday", today: today) == LocalDate(year: 2026, month: 9, day: 30))
        #expect(TimeWords.day("2026-02-29", today: today) == nil)
        #expect(TimeWords.date(day: 30, month: 12, today: today) == LocalDate(year: 2025, month: 12, day: 30))
    }
}

@Suite struct PaletteTests {
    @Test func namesColors() {
        #expect(Palette.color(named: "Teal") == "#4BACC6")
        #expect(Palette.color(named: "grey") == "#7F7F7F")
        #expect(Palette.color(named: "4bacc6") == "#4BACC6")
        #expect(Palette.color(named: "#12345") == nil)
        #expect(Palette.name(of: "#4bacc6") == "Teal")
        #expect(Palette.name(of: "#123456") == "#123456")
    }

    @Test func offersTheFirstColorNoProjectUses() {
        #expect(Palette.next(in: CommandFixture.ledger()) == "#8064A2")
        #expect(Palette.next(in: Ledger()) == "#4F7CAC")
    }
}
