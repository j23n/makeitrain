#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import TrackerCore
@testable import MacUI
@testable import TrackerKit

/// Renders the Mac screens with sample data into PNG files, to look at them
/// without running the app. Runs only when SCREENSHOTS_DIR names the folder
/// to write to, as in CI's screenshots job.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"] != nil))
@MainActor
struct Screenshots {
    @Test func renderTheScreens() async throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"]!, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let sample = SampleData()
        defer { sample.cleanUp() }
        let model = await sample.model()
        let size = CGSize(width: 1200, height: 740)

        for screen in Screen.allCases {
            try render(MainWindow(model: model, screen: screen), size: size, to: folder.appendingPathComponent("main-\(screen.rawValue).png"))
        }
        try render(MenuBarPopover(model: model), size: nil, to: folder.appendingPathComponent("menu-bar.png"))
        try render(SettingsView(model: model), size: nil, to: folder.appendingPathComponent("settings.png"))

        // The inspectors, with something selected.
        try render(EntriesView(model: model, selection: [sample.ids["Call with Globex"]!]), size: size, to: folder.appendingPathComponent("editor-entry.png"))
        let tuesday = ["Moodboard", "Hero section", "Offline mode"].map { sample.ids[$0]! }
        try render(EntriesView(model: model, selection: Set(tuesday)), size: size, to: folder.appendingPathComponent("editor-entries.png"))
        try render(DayTimelineScreen(model: model, selection: sample.ids["Landing page copy"]!), size: size, to: folder.appendingPathComponent("editor-timeline.png"))
        try render(ProjectsView(model: model, selection: .project(sample.ids["Website redesign"]!)), size: size, to: folder.appendingPathComponent("editor-project.png"))
        try render(ProjectsView(model: model, selection: .client(sample.ids["Acme"]!)), size: size, to: folder.appendingPathComponent("editor-client.png"))
        try render(TagsView(model: model, selection: "design"), size: size, to: folder.appendingPathComponent("editor-tag.png"))

        // The project picker's list, as it opens and while searching.
        let website = ProjectChoice.project(sample.ids["Website redesign"]!)
        try render(
            ProjectChooser(ledger: model.ledger, current: website, choose: { _ in }, cancel: {}).frame(width: 320),
            size: nil,
            to: folder.appendingPathComponent("chooser.png")
        )
        try render(
            ProjectChooser(ledger: model.ledger, current: website, query: "re", choose: { _ in }, cancel: {}).frame(width: 320),
            size: nil,
            to: folder.appendingPathComponent("chooser-search.png")
        )
    }

    struct RenderError: Error {}

    /// Shows the view in a window, lets SwiftUI and AppKit settle, and saves
    /// the whole window, title bar and toolbar included.
    func render(_ view: some View, size: CGSize?, to file: URL) throws {
        let controller = NSHostingController(rootView: view)
        controller.sceneBridgingOptions = [.toolbars, .title]
        controller.sizingOptions = size == nil ? [.preferredContentSize] : []
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "Time Tracker"
        window.setContentSize(size ?? controller.view.fittingSize)
        window.makeKeyAndOrderFront(nil)
        settle()
        if size == nil {
            window.setContentSize(controller.view.fittingSize)
            settle()
        }

        let frameView = window.contentView?.superview ?? controller.view
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { throw RenderError() }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderError() }
        try png.write(to: file)
        window.orderOut(nil)
    }

    private func settle() {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
    }
}

/// A week of entries for a designer who works for two clients, with a
/// running timer, an overlap, an unassigned entry and one recorded in New
/// York. "Now" is Wednesday, September 23, 2026, at 15:40 in Berlin.
@MainActor
final class SampleData {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    /// Ids of the clients, projects and entries, by name or note.
    var ids: [String: UUID] = [:]

    init() {
        let name = "Screenshots-\(UUID().uuidString)"
        root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        suiteName = name
        defaults = UserDefaults(suiteName: name)!
    }

    func model() async -> AppModel {
        let now = DateTimeFormat.parse("2026-09-23T15:40:00+02:00")!
        let model = AppModel(environment: AppEnvironment(
            localFolder: root.appendingPathComponent("Data"),
            backupsFolder: root.appendingPathComponent("Backups"),
            defaults: defaults,
            now: { now },
            timeZone: { "Europe/Berlin" }
        ))
        model.firstWeekday = 2
        await model.start()

        let acme = model.addClient(named: "Acme", undoManager: nil)
        let globex = model.addClient(named: "Globex", undoManager: nil)
        let website = model.addProject(named: "Website redesign", client: acme, color: "#4F7CAC", undoManager: nil)
        let app = model.addProject(named: "Mobile app", client: acme, color: "#C0504D", undoManager: nil)
        let brand = model.addProject(named: "Brand refresh", client: globex, color: "#9BBB59", undoManager: nil)
        let internalWork = model.addProject(named: "Internal", client: nil, color: "#8064A2", undoManager: nil)
        let admin = model.addProject(named: "Admin", client: nil, color: "#7F7F7F", undoManager: nil)
        model.updateProject(admin, undoManager: nil) { $0.archived = true }
        ids["Acme"] = acme
        ids["Website redesign"] = website

        func add(_ project: UUID?, _ start: String, _ end: String, _ note: String, _ tags: [String] = [], zone: String = "Europe/Berlin", offset: String = "+02:00") {
            let startTime = DateTimeFormat.parse("2026-09-\(start):00\(offset)")!
            let endTime = DateTimeFormat.parse("2026-09-\(end):00\(offset)")!
            let entry = TimeEntry(projectID: project, start: startTime, end: endTime, timeZone: zone, tags: tags, note: note, updated: startTime)
            model.addEntry(entry, undoManager: nil)
            ids[note] = entry.id
        }

        add(brand, "18T10:00", "18T12:00", "Client visit", ["client-call"], zone: "America/New_York", offset: "-04:00")
        add(admin, "18T14:00", "18T15:00", "Expenses")

        add(website, "21T09:00", "21T11:30", "Wireframe review, round 2", ["design", "client-call"])
        add(internalWork, "21T11:30", "21T12:15", "Planning")
        add(app, "21T13:00", "21T17:00", "Sync engine", ["development"])

        add(brand, "22T08:45", "22T10:00", "Moodboard", ["design"])
        add(website, "22T10:00", "22T12:30", "Hero section", ["design"])
        add(app, "22T13:30", "22T16:00", "Offline mode", ["development"])
        add(brand, "22T15:30", "22T16:30", "Call with Globex", ["client-call"])

        add(website, "23T09:00", "23T10:30", "Kickoff with the new team", ["client-call"])
        add(internalWork, "23T10:30", "23T12:00", "Invoices")
        add(nil, "23T12:00", "23T12:20", "Email")
        add(app, "23T13:00", "23T14:30", "Code review", ["development"])

        model.startTimer(Combination(projectID: website, tags: ["design"]), note: "Landing page copy", undoManager: nil)
        model.setRunningStart(DateTimeFormat.parse("2026-09-23T14:45:00+02:00")!, undoManager: nil)
        ids["Landing page copy"] = model.running?.id
        return model
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
#endif
