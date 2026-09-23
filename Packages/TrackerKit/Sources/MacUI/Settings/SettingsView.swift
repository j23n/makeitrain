#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI
import TrackerKit

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var switching = false
    @State private var switchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Keep data in iCloud Drive", isOn: iCloudBinding)
                    .disabled(switching || (!model.isICloudAvailable && model.storage == .local))
                Text(storageExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Show in Finder") {
                        show(model.dataFolder)
                    }
                    Button("Show Backups in Finder") {
                        show(model.backupsFolder)
                    }
                }
            } header: {
                Text("Storage")
            }

            Section {
                Picker("First day of the week", selection: $model.firstWeekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
            } header: {
                Text("Reports")
            }

            Section {
                LaunchAtLoginToggle()
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .alert("Couldn't Switch Storage", isPresented: Binding(get: { switchError != nil }, set: { if !$0 { switchError = nil } })) {
            Button("OK") { switchError = nil }
        } message: {
            Text(switchError ?? "")
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
                    } catch AppModel.StorageError.iCloudNotDownloaded {
                        switchError = "Some of your data hasn't downloaded from iCloud yet. Try again once it has."
                    } catch AppModel.StorageError.iCloudUnavailable {
                        switchError = "Sign in to iCloud and turn on iCloud Drive first."
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
            "Your data syncs through iCloud Drive to your other devices. Turning this off copies it to this Mac and leaves iCloud as it is."
        case .local:
            model.isICloudAvailable
                ? "Your data stays on this Mac. Turning iCloud on merges it with any data already in iCloud Drive."
                : "Your data stays on this Mac. Sign in to iCloud to sync it."
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
    }
}
#endif
