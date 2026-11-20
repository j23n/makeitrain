#if os(iOS)
#if FEEDBACK
import FeedbackKit
#endif
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit
import UniformTypeIdentifiers

/// The iPhone's and iPad's settings: how the app looks, starting timers
/// from outside it, where the data is and what's in it, importing and
/// exporting, and which calendar on this device belongs to which project.
struct MobileSettings: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var importing = false
    @State private var importingEvents = false
    @State private var export: ExportDocument?
    @State private var exportName = ""
    @State private var exporting = false

    var body: some View {
        @Bindable var preferences = model.preferences
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $preferences.appearance) {
                        ForEach(Preferences.Appearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Toggle("Live Activity", isOn: $preferences.showsLiveActivity)
                    NavigationLink("Shortcuts and controls") {
                        MobileShortcutsHelp()
                    }
                }

                Section("General") {
                    WeekStartPicker(model: model)
                    Toggle("Contract alerts", isOn: $preferences.contractAlerts)
                        .onChange(of: preferences.contractAlerts) { model.updateContractAlerts() }
                }

                #if FEEDBACK
                FeedbackSettingsSection(center: Feedback.center)
                #endif

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: model.storage == .iCloud ? "icloud" : deviceName.lowercased())
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.storageLocation)
                            Text(model.saveStatus)
                                .font(.footnote)
                                .foregroundStyle(Theme.text3)
                        }
                    }
                    ICloudToggle(model: model)
                    NavigationLink {
                        MobileDataFiles(model: model)
                    } label: {
                        LabeledContent("Files", value: model.filesSummary)
                    }
                    LabeledContent("Latest backup", value: model.latestBackup ?? "None yet")
                    BackUpButton(model: model)
                } header: {
                    Text("Data")
                } footer: {
                    Text(model.storageExplanation)
                }

                Section {
                    Button("Import CSV…") { importing = true }
                        .disabled(model.isReadOnly)
                    Button("Import Calendar Events…") { importingEvents = true }
                        .disabled(model.isReadOnly)
                    Button("Export All Entries…", action: exportAll)
                        .disabled(!model.hasFinishedEntries)
                } header: {
                    Text("Import and export")
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
        }
        .csvImporter(isPresented: $importing, model: model, undoManager: undoManager)
        .sheet(isPresented: $importingEvents) {
            CalendarImportSheet(model: model, undoManager: undoManager)
        }
        .fileExporter(isPresented: $exporting, document: export, contentType: .commaSeparatedText, defaultFilename: exportName) { _ in }
    }

    private func exportAll() {
        guard let csv = model.finishedEntriesCSV() else { return }
        export = csv.document
        exportName = csv.fileName
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
                Text("Denied. Allow it in Settings › Privacy & Security.")
                    .foregroundStyle(Theme.text2)
            case .restricted:
                Text("Calendar access is restricted on this \(deviceName).")
                    .foregroundStyle(Theme.text2)
            case .granted:
                if model.calendars.isEmpty {
                    Text("No calendars on this \(deviceName).")
                        .foregroundStyle(Theme.text2)
                }
                ForEach(model.calendars) { calendar in
                    CalendarProjectPicker(model: model, calendar: calendar) {
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
            Text("Calendars on this \(deviceName)")
        }
    }
}

/// The data files, with what each holds or why it can't be read.
struct MobileDataFiles: View {
    let model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(model.dataFiles) { file in
                    DataFileRow(file, stacked: true)
                }
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What can start, stop or switch timers from outside the app.
struct MobileShortcutsHelp: View {
    var body: some View {
        List {
            Section {
                row("Start a Timer", "Asks what to start, as typed in the command line.")
                Text("Stop the Timer")
                Text("Open the Command Line")
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Run them with Siri, the Shortcuts app, the Action button or Back Tap.")
            }
            Section {
                Text("Add the Command Line or Stop the Timer control in Control Center or on the Lock Screen. For the Action button, choose a Time Tracker shortcut in Settings › Action Button.")
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
