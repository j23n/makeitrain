#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit
import UniformTypeIdentifiers

/// The iPhone's settings: how the app looks, starting timers from outside
/// it, where the data is and what's in it, importing and exporting, and
/// which calendar on this iPhone belongs to which project.
struct PhoneSettings: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var switching = false
    @State private var switchError: String?
    @State private var backingUp = false
    @State private var importing = false
    @State private var importRequest: ImportRequest?
    @State private var importError: String?
    @State private var importingEvents = false
    @State private var export: CSVDocument?
    @State private var exportName = ""
    @State private var exporting = false

    private var preferences: Preferences { model.preferences }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: Binding(get: { preferences.appearance }, set: { preferences.appearance = $0 })) {
                        ForEach(Preferences.Appearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Quick start") {
                    Toggle(isOn: Binding(get: { preferences.showsLiveActivity }, set: { preferences.showsLiveActivity = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live Activity")
                            Text("The running timer on the Lock Screen")
                                .font(.footnote)
                                .foregroundStyle(Theme.text3)
                        }
                    }
                    NavigationLink {
                        PhoneShortcutsHelp()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shortcuts and controls")
                            Text("Start, stop or switch from Control Center, the Lock Screen or the Action button")
                                .font(.footnote)
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }

                Section("General") {
                    Picker("Weeks start on", selection: $model.firstWeekday) {
                        ForEach([2, 1, 7], id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: model.storage == .iCloud ? "icloud" : "iphone")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.storage == .iCloud ? "iCloud Drive › Time Tracker" : "On this iPhone")
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(Theme.text3)
                        }
                    }
                    Toggle("Keep data in iCloud Drive", isOn: iCloudBinding)
                        .disabled(switching || (!model.isICloudAvailable && model.storage == .local))
                    NavigationLink {
                        PhoneDataFiles(model: model)
                    } label: {
                        LabeledContent("Files", value: filesSummary)
                    }
                    LabeledContent("Backups", value: "daily, \(model.backupNames.count) kept")
                    Button(backingUp ? "Backing Up…" : "Back Up Now") {
                        backingUp = true
                        Task {
                            try? await model.backUpNow()
                            backingUp = false
                        }
                    }
                    .disabled(backingUp)
                } header: {
                    Text("Data")
                } footer: {
                    Text(storageExplanation)
                }

                Section {
                    Button("Import CSV…") { importing = true }
                        .disabled(model.isReadOnly)
                    Button("Import Calendar Events…") { importingEvents = true }
                        .disabled(model.isReadOnly)
                    Button("Export All Entries…", action: exportAll)
                        .disabled(!model.resolved.contains { !$0.isRunning })
                } header: {
                    Text("Import and export")
                } footer: {
                    Text("Exports have the columns date, start, end, hours, client, project, tags, note. Imports show what they add before anything changes.")
                }

                calendars

                MobileNotices(model: model)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            model.refreshCalendars()
            handle(model.request)
        }
        .alert("Couldn't Switch Storage", isPresented: Binding(get: { switchError != nil }, set: { if !$0 { switchError = nil } })) {
            Button("OK") { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            do {
                importRequest = try model.importRequest(forFileAt: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .sheet(item: $importRequest) { request in
            MobileImportSheet(model: model, request: request)
        }
        .sheet(isPresented: $importingEvents) {
            MobileCalendarImportSheet(model: model)
        }
        .alert("Couldn't Import the File", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .fileExporter(isPresented: $exporting, document: export, contentType: .commaSeparatedText, defaultFilename: exportName) { _ in }
    }

    /// Imports or exports, as another part of the app asked.
    private func handle(_ request: AppRequest?) {
        switch request {
        case .importCSV?:
            importing = true
        case .importEvents?:
            importingEvents = true
        case .exportEntries?:
            exportAll()
        default:
            return
        }
        model.request = nil
    }

    private func exportAll() {
        let entries = model.resolved.filter { !$0.isRunning }
        guard let name = CSVExport.fileName(for: entries) else { return }
        export = CSVDocument(data: CSVExport.data(for: entries, ledger: model.ledger))
        exportName = name
        exporting = true
    }

    // MARK: Calendars

    @ViewBuilder
    private var calendars: some View {
        Section {
            switch model.calendarAccess {
            case .notDetermined:
                Button("Allow Access to Calendars") {
                    Task { await model.requestCalendarAccess() }
                }
            case .denied:
                Text("Time Tracker isn't allowed to read your calendars. Allow it in the Settings app, under Privacy & Security.")
                    .foregroundStyle(Theme.text2)
            case .restricted:
                Text("Reading calendars isn't allowed on this iPhone.")
                    .foregroundStyle(Theme.text2)
            case .granted:
                if model.calendars.isEmpty {
                    Text("No calendars on this iPhone.")
                        .foregroundStyle(Theme.text2)
                }
                ForEach(sortedCalendars) { calendar in
                    Picker(selection: projectBinding(for: calendar)) {
                        Text("None").tag(UUID?.none)
                        ForEach(model.ledger.pickerProjects()) { project in
                            Text(model.ledger.projectTitle(project.id)).tag(UUID?.some(project.id))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.title)
                            if !calendar.account.isEmpty {
                                Text(calendar.account)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.text3)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Calendars on this iPhone")
        } footer: {
            Text("A project's calendar shows its events in the week until you log them. These settings stay on this iPhone; clients, projects and entries sync through your files.")
        }
    }

    private var sortedCalendars: [CalendarInfo] {
        model.calendars.sorted { a, b in
            a.account != b.account
                ? a.account.localizedStandardCompare(b.account) == .orderedAscending
                : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// The project a calendar belongs to: choosing one links them, and
    /// None unlinks it.
    private func projectBinding(for calendar: CalendarInfo) -> Binding<UUID?> {
        Binding(
            get: { model.linkedProject(of: calendar.id) },
            set: { projectID in
                if let projectID {
                    model.setCalendar(calendar.id, forProject: projectID)
                } else if let linked = model.linkedProject(of: calendar.id) {
                    model.setCalendar(nil, forProject: linked)
                }
            }
        )
    }

    // MARK: Data

    private var status: String {
        if model.hasUnsavedChanges {
            return "Saving…"
        }
        if let saved = model.lastSaved {
            return "Up to date, saved at \(Format.time(saved, zone: model.environment.timeZone()))"
        }
        return model.state == .ready ? "Up to date" : "Opening…"
    }

    private var filesSummary: String {
        let files = model.dataFiles
        let unread = files.filter { $0.problem != nil }.count
        return unread == 0 ? "\(files.count), all read" : "\(files.count), \(unread) not read"
    }

    private var storageExplanation: String {
        switch model.storage {
        case .iCloud:
            "Turning this off copies everything to this iPhone and leaves iCloud as it is, so your other devices keep syncing."
        case .local:
            model.isICloudAvailable
                ? "Turning this on merges your data with any already in iCloud Drive."
                : "Sign in to iCloud to sync your data."
        }
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
}

/// The data files, with what each holds or why it can't be read.
struct PhoneDataFiles: View {
    let model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(model.dataFiles) { file in
                    HStack(spacing: 10) {
                        Image(systemName: file.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(file.problem == nil ? Theme.ok : Theme.amber)
                            .accessibilityLabel(Text(file.problem == nil ? "Read" : "Not read"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.path)
                                .font(.system(size: 14, design: .monospaced))
                            Text(file.problem.map(describe) ?? file.contents)
                                .font(.footnote)
                                .foregroundStyle(file.problem == nil ? Theme.text2 : Theme.amberText)
                        }
                    }
                }
            } footer: {
                Text("Plain JSON, one file per month. Edit one by hand and the app merges your edit; a file it can't read is never overwritten.")
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func describe(_ problem: FileProblem) -> String {
        switch problem {
        case .unreadable: "Can't be read, so it's left as it is."
        case let .newerVersion(version): "Written by a newer version of the app (\(version)), so it's left as it is."
        case .notDownloaded: "Not downloaded from iCloud yet."
        }
    }
}

/// What can start, stop or switch timers from outside the app.
struct PhoneShortcutsHelp: View {
    var body: some View {
        List {
            Section {
                row("Start a Timer", "Asks what you're working on, as you'd type it in the command line, such as bookings #227 export.")
                row("Stop the Timer", "Stops the running timer.")
                row("Open the Command Line", "Opens Time Tracker with the command line ready to type in.")
            } header: {
                Text("In the Shortcuts app")
            } footer: {
                Text("Ask Siri, or run them from the Shortcuts app, a widget, the Action button or Back Tap.")
            }
            Section {
                Text("In Control Center, tap + and add Time Tracker's Start or Stop control. On the Lock Screen, customize it and add one of the same controls. On iPhones with an Action button, choose a Time Tracker shortcut for it in the Settings app, under Action Button.")
                    .foregroundStyle(Theme.text2)
            } header: {
                Text("Controls")
            }
        }
        .navigationTitle("Shortcuts and controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Theme.text3)
        }
    }
}
#endif
