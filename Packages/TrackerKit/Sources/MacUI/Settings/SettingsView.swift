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
    let model: AppModel
    @State private var recording = false
    @State private var monitor: Any?
    @State private var showsCheatSheet = false

    var body: some View {
        @Bindable var preferences = model.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "Appearance") {
                    SettingsRow(title: "Light or dark", divided: false) {
                        SegmentPicker(
                            Preferences.Appearance.allCases.map { (value: $0, title: $0.title) },
                            selection: $preferences.appearance
                        )
                    }
                }

                SettingsSection(title: "General") {
                    SettingsRow(title: "Open at login", divided: false) {
                        LaunchAtLoginToggle()
                    }
                    SettingsRow(title: "Weeks start on") {
                        WeekStartPicker(model: model)
                            .labelsHidden()
                            .fixedSize()
                    }
                }

                SettingsSection(title: "Command line") {
                    SettingsRow(title: "Keyboard shortcut", divided: false) {
                        HStack(spacing: 8) {
                            if recording {
                                Text("Type a shortcut…")
                                    .foregroundStyle(Theme.text2)
                            } else if let shortcut = preferences.shortcut {
                                KeyCap(shortcut.title)
                                Button("Remove") {
                                    preferences.shortcut = nil
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
                    SettingsRow(title: "Close after Return") {
                        Toggle("Close after Return", isOn: $preferences.closesAfterReturn)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    SettingsRow(title: "Commands") {
                        Button("Show") {
                            showsCheatSheet = true
                        }
                        .buttonStyle(.link)
                    }
                }

                SettingsSection(title: "Menu bar") {
                    SettingsRow(title: "Show elapsed time", divided: false) {
                        Toggle("Show elapsed time", isOn: $preferences.menuBarShowsTime)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    SettingsRow(title: "Show project name") {
                        Toggle("Show project name", isOn: $preferences.menuBarShowsProject)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!preferences.menuBarShowsTime)
                    }
                    SettingsRow(title: "Show when there are corrections") {
                        Toggle("Show when there are corrections", isOn: $preferences.menuBarMarksCorrections)
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
            model.preferences.shortcut = shortcut
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
            Row(example: "web #12 Fix login", meaning: "Start Website with the tag #12 and a note, or switch to it"),
            Row(example: "web #12", meaning: "Use the note of the last entry tagged #12"),
            Row(example: "brand from 11:05", meaning: "Switch, starting at 11:05"),
            Row(example: "brand -15m", meaning: "Switch, starting 15 minutes ago"),
            Row(example: "from 10:30", meaning: "Change the running timer's start to 10:30"),
            Row(example: "stop", meaning: "Stop now. Also stop 11:05 or stop -10m"),
        ]),
        Topic(title: "Logging time", rows: [
            Row(example: "web review 9:00-10:30", meaning: "Log a finished entry. Also 9-10:30 or 9am-11am"),
            Row(example: "web review wed 14-16", meaning: "Log on another day: yesterday, wed, 30 sep, 2026-09-30"),
            Row(example: "web review for 45m", meaning: "Log 45 minutes ending now"),
            Row(example: "⌥⏎", meaning: "Log the line as finished, from the end of the last entry"),
        ]),
        Topic(title: "Clients and projects", rows: [
            Row(example: "new project App for acme", meaning: "Add a project, and its client if it's new"),
            Row(example: "new client Globex", meaning: "Add a client"),
            Row(example: "archive brand", meaning: "Archive a project or client"),
            Row(example: "unarchive brand", meaning: "Bring it back"),
            Row(example: "color web teal", meaning: "Blue, red, green, purple, orange, teal, gold or gray"),
            Row(example: "rename web to Website v2", meaning: "Rename a project or client"),
            Row(example: "merge acme2 into acme", meaning: "Move everything to the second, then delete the first"),
        ]),
        Topic(title: "Search", rows: [
            Row(example: "find login", meaning: "List the entries with these words"),
            Row(example: "↑ and ↓", meaning: "Previous lines, then today's entries"),
            Row(example: "⇥", meaning: "Complete the line from the last matching entry"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Commands")
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "Location") {
                    SettingsRow(title: model.storageLocation, detail: model.saveStatus, divided: false) {
                        Button("Show in Finder") {
                            show(model.dataFolder)
                        }
                        .buttonStyle(ChoiceButtonStyle(compact: true))
                    }
                    SettingsRow(title: "Keep data in iCloud Drive", detail: model.storageExplanation) {
                        ICloudToggle(model: model)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                SettingsSection(title: "Files") {
                    ForEach(Array(model.dataFiles.prefix(13).enumerated()), id: \.element.id) { index, file in
                        VStack(spacing: 0) {
                            if index > 0 {
                                Divider().overlay(Theme.line)
                            }
                            HStack(spacing: 10) {
                                Image(systemName: file.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(file.problem == nil ? Theme.ok : Theme.amber)
                                    .accessibilityLabel(Text(file.problem == nil ? "Loaded" : "Not loaded"))
                                Text(file.path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 190, alignment: .leading)
                                Text(file.detail)
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
                    SettingsRow(title: "Latest backup", detail: model.latestBackup ?? "None yet", divided: false) {
                        HStack(spacing: 8) {
                            BackUpButton(model: model)
                            Button("Show in Finder") {
                                show(model.environment.backupsFolder)
                            }
                        }
                        .buttonStyle(ChoiceButtonStyle(compact: true))
                    }
                }

                SettingsSection(
                    title: "Calendars on this Mac",
                    footer: "Link a calendar on a project's page."
                ) {
                    SettingsRow(title: "Calendar access", divided: false) {
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

                SettingsSection(title: "Import and export") {
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
            Text("Denied. Allow it in System Settings › Privacy & Security.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
        }
    }

    /// Asks the main window to import or export, opening it first.
    private func ask(_ request: AppRequest) {
        model.request = request
        openWindow(id: WindowID.main)
        NSApp.activate()
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
