#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI
import TrackerCore
import TrackerKit

/// Settings in two panes: General, for how the app looks and behaves on
/// this Mac, and Data, for where the files are and what's in them.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            DataSettings(model: model)
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 640, height: 680)
    }
}

/// A titled group of rows on a card, as Settings lays them out.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One row of a settings card: a title, an explanation under it, and a
/// control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    var divided = true
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            if divided {
                Divider().overlay(Theme.line)
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.text)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var recording = false
    @State private var monitor: Any?
    @State private var showsCheatSheet = false

    private var preferences: Preferences { model.preferences }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "Appearance") {
                    SettingsRow(title: "Light or dark", detail: "System follows macOS and switches with it.", divided: false) {
                        SegmentPicker(
                            Preferences.Appearance.allCases.map { (value: $0, title: $0.title) },
                            selection: Binding(get: { preferences.appearance }, set: { preferences.appearance = $0 })
                        )
                    }
                }

                SettingsSection(title: "General") {
                    SettingsRow(title: "Open at login", divided: false) {
                        LaunchAtLoginToggle()
                    }
                    SettingsRow(title: "Weeks start on") {
                        Picker("Weeks start on", selection: $model.firstWeekday) {
                            ForEach([2, 1, 7], id: \.self) { day in
                                Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                SettingsSection(title: "Command line") {
                    SettingsRow(title: "Open it from anywhere", detail: "Over any app, without touching the menu bar.", divided: false) {
                        HStack(spacing: 8) {
                            if recording {
                                Text("Type a shortcut…")
                                    .foregroundStyle(Theme.text2)
                            } else if let shortcut = preferences.shortcut {
                                KeyCap(shortcut.title)
                                Button("Remove") {
                                    preferences.shortcut = nil
                                    registerShortcut()
                                }
                                .buttonStyle(ChoiceButtonStyle(compact: true))
                            } else {
                                Text("None")
                                    .foregroundStyle(Theme.text3)
                            }
                            Button(recording ? "Cancel" : "Change…") {
                                if recording {
                                    stopRecording()
                                } else {
                                    startRecording()
                                }
                            }
                            .buttonStyle(ChoiceButtonStyle(compact: true))
                        }
                    }
                    SettingsRow(title: "Close it after Return", detail: "Leave it on to start a timer and get back to work.") {
                        Toggle("Close it after Return", isOn: Binding(get: { preferences.closesAfterReturn }, set: { preferences.closesAfterReturn = $0 }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    SettingsRow(title: "Everything you can type, with examples") {
                        Button("Show the cheat sheet") {
                            showsCheatSheet = true
                        }
                        .buttonStyle(.link)
                    }
                }

                SettingsSection(
                    title: "Menu bar",
                    footer: "These settings stay on this Mac. Clients, projects and entries are in your data files, and those sync."
                ) {
                    SettingsRow(title: "Show the running time", divided: false) {
                        Toggle("Show the running time", isOn: Binding(get: { preferences.menuBarShowsTime }, set: { preferences.menuBarShowsTime = $0 }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    SettingsRow(title: "Show the project's name too") {
                        Toggle("Show the project's name too", isOn: Binding(get: { preferences.menuBarShowsProject }, set: { preferences.menuBarShowsProject = $0 }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!preferences.menuBarShowsTime)
                    }
                    SettingsRow(title: "Mark it when something needs correcting", detail: "Overlaps, overnight timers, entries with no project, events not logged.") {
                        Toggle("Mark it when something needs correcting", isOn: Binding(get: { preferences.menuBarMarksCorrections }, set: { preferences.menuBarMarksCorrections = $0 }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.background)
        .sheet(isPresented: $showsCheatSheet) {
            CheatSheet()
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            guard let shortcut = HotKey.shortcut(from: event) else { return nil }
            preferences.shortcut = shortcut
            registerShortcut()
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func registerShortcut() {
        (NSApp.delegate as? AppDelegate)?.registerShortcut()
    }
}

/// Everything the command line understands, with an example of each.
struct CheatSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let example: String
        let meaning: String
        var id: String { example }
    }

    private struct Topic: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    private let groups: [Topic] = [
        Topic(title: "Timers", rows: [
            Row(example: "book #227 Export to PDF", meaning: "Start Bookings with the tag #227 and a note, or switch to it"),
            Row(example: "book #227", meaning: "The note comes from the last entry with #227"),
            Row(example: "harbor from 11:05", meaning: "Switch, as if you had at 11:05"),
            Row(example: "harbor -15m", meaning: "Switch, as if you had 15 minutes ago"),
            Row(example: "from 10:30", meaning: "The running timer started at 10:30"),
            Row(example: "stop", meaning: "Stop now; stop 11:05 or stop -10m for earlier"),
        ]),
        Topic(title: "Logging time", rows: [
            Row(example: "book review 9:00-10:30", meaning: "Log a finished entry; also 9-10:30, 9am-11am"),
            Row(example: "book review wed 14-16", meaning: "On another day: yesterday, wed, 30 sep, 2026-09-30"),
            Row(example: "book review for 45m", meaning: "Log 45 minutes that end now"),
            Row(example: "⌥⏎", meaning: "Log what's typed as done, since the last entry ended"),
        ]),
        Topic(title: "Clients and projects", rows: [
            Row(example: "new project Phoenix for zenith", meaning: "Add a project, and its client if that's new"),
            Row(example: "new client Acme", meaning: "Add a client"),
            Row(example: "archive harbor", meaning: "Archive a project or client; unarchive brings it back"),
            Row(example: "color book teal", meaning: "Blue, red, green, purple, orange, teal, gold or gray"),
            Row(example: "rename book to Bookings Pro", meaning: "Rename a project or client"),
            Row(example: "merge zenith2 into zenith", meaning: "Move everything over, then delete the first"),
        ]),
        Topic(title: "Finding", rows: [
            Row(example: "find export pdf", meaning: "List the entries with those words"),
            Row(example: "↑ and ↓", meaning: "Earlier lines, and today so far"),
            Row(example: "⇥", meaning: "Finish the line from the last entry like it"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Everything you can type")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.text2)
                            ForEach(group.rows) { row in
                                HStack(alignment: .firstTextBaseline, spacing: 14) {
                                    Text(row.example)
                                        .font(Theme.commandFont(size: 12.5))
                                        .foregroundStyle(Theme.text)
                                        .frame(width: 250, alignment: .leading)
                                    Text(row.meaning)
                                        .foregroundStyle(Theme.text2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 560)
        .background(Theme.background)
    }
}

// MARK: - Data

struct DataSettings: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var switching = false
    @State private var switchError: String?
    @State private var backingUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "Where your data is") {
                    SettingsRow(title: location, detail: status, divided: false) {
                        Button("Show in Finder") {
                            show(model.dataFolder)
                        }
                        .buttonStyle(ChoiceButtonStyle(compact: true))
                    }
                    SettingsRow(title: "Keep data in iCloud Drive", detail: storageExplanation) {
                        Toggle("Keep data in iCloud Drive", isOn: iCloudBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(switching || (!model.isICloudAvailable && model.storage == .local))
                    }
                }

                SettingsSection(
                    title: "Files",
                    footer: "Plain JSON, one file per month. Edit one by hand and the app merges your edit; a file it can't read is never overwritten."
                ) {
                    ForEach(Array(model.dataFiles.prefix(13).enumerated()), id: \.element.id) { index, file in
                        VStack(spacing: 0) {
                            if index > 0 {
                                Divider().overlay(Theme.line)
                            }
                            HStack(spacing: 10) {
                                Image(systemName: file.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(file.problem == nil ? Theme.ok : Theme.amber)
                                    .accessibilityLabel(Text(file.problem == nil ? "Read" : "Not read"))
                                Text(file.path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 190, alignment: .leading)
                                Text(file.problem.map { describe($0) } ?? file.contents)
                                    .font(.system(size: 12))
                                    .foregroundStyle(file.problem == nil ? Theme.text2 : Theme.amberText)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                        }
                    }
                }

                SettingsSection(title: "Backups") {
                    SettingsRow(title: "Every day, and before you switch storage", detail: backupDetail, divided: false) {
                        HStack(spacing: 8) {
                            Button("Back Up Now") {
                                backingUp = true
                                Task {
                                    try? await model.backUpNow()
                                    backingUp = false
                                }
                            }
                            .disabled(backingUp)
                            Button("Show in Finder") {
                                show(model.backupsFolder)
                            }
                        }
                        .buttonStyle(ChoiceButtonStyle(compact: true))
                    }
                }

                SettingsSection(
                    title: "Calendars on this Mac",
                    footer: "Links stay on this Mac, since each device names its calendars differently. Change one on the project's page."
                ) {
                    SettingsRow(title: "Access to your calendars", divided: false) {
                        calendarAccess
                    }
                    ForEach(model.calendars.filter { model.linkedProject(of: $0.id) != nil }) { calendar in
                        SettingsRow(title: calendar.title, detail: calendar.account) {
                            HStack(spacing: 7) {
                                Text("→").foregroundStyle(Theme.text3)
                                ProjectName(ledger: model.ledger, projectID: model.linkedProject(of: calendar.id))
                            }
                        }
                    }
                }

                SettingsSection(
                    title: "Import and export",
                    footer: "Exports have the columns date, start, end, hours, client, project, tags, note. Imports show what they add before anything changes."
                ) {
                    HStack(spacing: 8) {
                        Button("Import CSV…") { ask(.importCSV) }
                        Button("Import Calendar Events…") { ask(.importEvents) }
                        Button("Export All Entries…") { ask(.exportEntries) }
                    }
                    .buttonStyle(ChoiceButtonStyle(compact: true))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .background(Theme.background)
        .onAppear { model.refreshCalendars() }
        .alert("Couldn't Switch Storage", isPresented: Binding(get: { switchError != nil }, set: { if !$0 { switchError = nil } })) {
            Button("OK") { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
    }

    private var location: String {
        model.storage == .iCloud ? "iCloud Drive › Time Tracker" : "On this Mac"
    }

    private var status: String {
        if model.hasUnsavedChanges {
            return "Saving…"
        }
        if let saved = model.lastSaved {
            return "Up to date · saved at \(Format.time(saved, zone: model.environment.timeZone()))"
        }
        return model.state == .ready ? "Up to date" : "Opening…"
    }

    private var backupDetail: String {
        let latest = model.backupNames.first.map { " The newest is \($0)." } ?? ""
        return "The 30 newest are kept on this Mac." + latest
    }

    @ViewBuilder
    private var calendarAccess: some View {
        switch model.calendarAccess {
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.ok)
        case .notDetermined:
            Button("Allow…") {
                Task { await model.requestCalendarAccess() }
            }
            .buttonStyle(ChoiceButtonStyle(compact: true))
        case .denied, .restricted:
            Text("Not allowed: turn it on in System Settings › Privacy & Security")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
        }
    }

    private func describe(_ problem: FileProblem) -> String {
        switch problem {
        case .unreadable: "Can't be read, so it's left as it is."
        case let .newerVersion(version): "Written by a newer version of the app (\(version)), so it's left as it is."
        case .notDownloaded: "Not downloaded from iCloud yet."
        }
    }

    /// Asks the main window to import or export, opening it first.
    private func ask(_ request: AppRequest) {
        model.request = request
        openWindow(id: WindowID.main)
        NSApp.activate()
    }

    private var iCloudBinding: Binding<Bool> {
        Binding(
            get: { model.storage == .iCloud },
            set: { on in
                switching = true
                Task {
                    do {
                        try await model.switchStorage(to: on ? .iCloud : .local)
                    } catch {
                        switchError = error.localizedDescription
                    }
                    switching = false
                }
            }
        )
    }

    private var storageExplanation: String {
        switch model.storage {
        case .iCloud:
            "Turning this off copies everything to this Mac and leaves iCloud as it is, so your other devices keep syncing."
        case .local:
            model.isICloudAvailable
                ? "Turning this on merges your data with any already in iCloud Drive."
                : "Sign in to iCloud to sync your data."
        }
    }

    private func show(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

/// Opens the app at login. Off until the user turns it on, as the App Store
/// requires.
struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at login", isOn: Binding(
            get: { enabled },
            set: { on in
                do {
                    if on {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // The toggle shows the actual status below.
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(model: PreviewData.model())
}
#endif
#endif
