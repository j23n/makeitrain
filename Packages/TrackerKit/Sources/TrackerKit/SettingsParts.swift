import SwiftUI
import TrackerCore
#if os(iOS)
import UIKit
#endif

// What the Mac's and the iPhone's and iPad's Settings share: where the data
// is and whether it's saved, keeping it in iCloud Drive, backing it up, and
// the first day of the week.

/// What this device is called in sentences, such as "Calendar on this
/// Mac".
@MainActor
public var deviceName: String {
    #if os(macOS)
    return "Mac"
    #else
    return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    #endif
}

extension AppModel {
    /// Where the data is, such as "iCloud Drive › Time Tracker" or "On this
    /// Mac".
    public var storageLocation: String {
        storage == .iCloud ? "iCloud Drive › Time Tracker" : "On this \(deviceName)"
    }

    /// Whether the data is saved, such as "Saving…" or "Saved at 15:40".
    public var saveStatus: String {
        if hasUnsavedChanges {
            return "Saving…"
        }
        if let lastSaved {
            return "Saved at \(Format.time(lastSaved, zone: environment.timeZone()))"
        }
        return state == .ready ? "Saved" : "Opening…"
    }

    /// What switching between iCloud Drive and this device does, or why
    /// iCloud Drive can't be chosen.
    public var storageExplanation: String {
        switch storage {
        case .iCloud:
            "Turning it off copies your data to this \(deviceName). The copy in iCloud stays."
        case .local:
            isICloudAvailable
                ? "Turning it on merges your data with what's in iCloud Drive."
                : "Sign in to iCloud to use it."
        }
    }
}

/// Keeps the data in iCloud Drive or on this device, copying it over when
/// switched, and says why when that fails.
public struct ICloudToggle: View {
    let model: AppModel
    @State private var switching = false
    @State private var failure: String?

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Toggle("Keep data in iCloud Drive", isOn: Binding(
            get: { model.storage == .iCloud },
            set: { on in
                switching = true
                Task {
                    do {
                        try await model.switchStorage(to: on ? .iCloud : .local)
                    } catch {
                        failure = error.localizedDescription
                    }
                    switching = false
                }
            }
        ))
        .disabled(switching || (!model.isICloudAvailable && model.storage == .local))
        .alert("Couldn't Switch Storage", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }
}

/// Backs the data up now. On iPhone and iPad it says so while it does.
public struct BackUpButton: View {
    let model: AppModel
    @State private var backingUp = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Button(title) {
            backingUp = true
            Task {
                try? await model.backUpNow()
                backingUp = false
            }
        }
        .disabled(backingUp)
    }

    private var title: String {
        #if os(macOS)
        return "Back Up Now"
        #else
        return backingUp ? "Backing Up…" : "Back Up Now"
        #endif
    }
}

/// The first day of the week: Monday, Sunday or Saturday.
public struct WeekStartPicker: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Picker("Weeks start on", selection: $model.firstWeekday) {
            ForEach([2, 1, 7], id: \.self) { day in
                Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
            }
        }
    }
}
