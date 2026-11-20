import SwiftUI
import TrackerCore

/// A contract to add or change, in a sheet: its hours, its first and last
/// day, and its alert. Nothing is kept until Save, so the alerts only
/// follow a saved contract; Cancel drops the changes.
public struct ContractSheet: View {
    let model: AppModel
    let projectID: UUID
    /// The contract as it was, or as it starts for a new one.
    let original: Contract
    let isNew: Bool
    @State private var draft: ContractDraft
    /// Why Save didn't keep the contract.
    @State private var problem: String?
    @State private var confirmingRemove = false
    /// The presenting window's, so that the change undoes there: on the
    /// Mac, a sheet has an undo manager of its own, gone once it closes.
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel, projectID: UUID, contract: Contract, isNew: Bool, undoManager: UndoManager?) {
        self.model = model
        self.undoManager = undoManager
        self.projectID = projectID
        self.original = contract
        self.isNew = isNew
        _draft = State(initialValue: ContractDraft(contract))
    }

    /// The contract to save.
    private var edited: Contract {
        draft.contract
    }

    private var hasChanges: Bool {
        isNew || edited != original
    }

    private var title: String {
        isNew ? "New Contract" : "Contract"
    }

    private var projectName: String {
        model.ledger.projects[projectID]?.name ?? "the project"
    }

    public var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], 20)
            Form {
                content
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Remove Contract…", role: .destructive) {
                        confirmingRemove = true
                    }
                    .disabled(model.isReadOnly)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || model.isReadOnly)
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 440, height: 500)
        .onChange(of: isGone) { closeIfGone() }
        .confirmationDialog(removeQuestion, isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: remove)
        }
        #else
        NavigationStack {
            Form {
                content
                if !isNew {
                    Section {
                        Button("Remove Contract", role: .destructive) {
                            confirmingRemove = true
                        }
                        .disabled(model.isReadOnly)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!hasChanges || model.isReadOnly)
                }
            }
            .confirmationDialog(removeQuestion, isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive, action: remove)
            }
        }
        .interactiveDismissDisabled(hasChanges && !isNew)
        .onChange(of: isGone) { closeIfGone() }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        Section {
            LabeledContent("Hours") {
                HStack(spacing: 4) {
                    TextField("Hours", text: $draft.hoursText)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .labelsHidden()
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: draft.hoursText) { problem = nil }
                    Text("h")
                        .foregroundStyle(Theme.text2)
                }
            }
            DatePicker("Starts", selection: day(\.start), displayedComponents: .date)
            DatePicker("Ends", selection: day(\.end), displayedComponents: .date)
        } footer: {
            if let problem {
                Text(problem)
                    .foregroundStyle(Theme.amberText)
            } else {
                Text(summary)
            }
        }
        alertSection
    }

    private var alertSection: some View {
        Section {
            Toggle("Alert", isOn: alertIsOn)
            if edited.alertsAt > 0 {
                Stepper(value: alertHours, in: 1...max(1, edited.hours)) {
                    LabeledContent("When left", value: Format.hours(edited.alertsAt))
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Alert")
        } footer: {
            Text(alertNote)
        }
    }

    /// Whether the contract alerts: off sets it to 0, and on back to 10%
    /// of the hours.
    private var alertIsOn: Binding<Bool> {
        Binding(
            get: { draft.alerts },
            set: { on in
                draft.alerts = on
                problem = nil
            }
        )
    }

    /// The hours left at which to alert. The default is kept as nil, so it
    /// follows the hours.
    private var alertHours: Binding<Int> {
        Binding(
            get: { draft.alertHours },
            set: { hours in
                draft.alertHours = hours
                problem = nil
            }
        )
    }

    /// What the contract counts, and the time on its days so far.
    private var summary: String {
        let contract = edited
        let counts = "Every entry of \(projectName) from \(Format.monthDay(contract.start)) to \(Format.monthDay(contract.end)) counts."
        guard contract.isValid else { return counts }
        let status = model.status(of: contract, projectID: projectID)
        guard status.hasStarted else { return counts }
        return "\(Format.duration(status.used)) logged so far, \(Format.left(status)). \(counts)"
    }

    /// What the alert does.
    private var alertNote: String {
        let contract = edited
        guard contract.alertsAt > 0 else {
            return "No alert for this contract. This \(deviceName) still notifies you when the hours run out."
        }
        let source = contract.alertHours == nil ? "10% of the hours unless you change it. " : ""
        return "\(source)This \(deviceName) notifies you when the time left reaches it, and when the hours run out."
    }

    private var removeQuestion: String {
        "Remove the contract for \(Format.days(original.days))?"
    }

    /// A picker's date for one of the contract's days.
    private func day(_ keyPath: WritableKeyPath<Contract, LocalDate>) -> Binding<Date> {
        Binding(
            get: { draft.base[keyPath: keyPath].pickerDate },
            set: { date in
                draft.base[keyPath: keyPath] = LocalDate(pickerDate: date)
                problem = nil
            }
        )
    }

    /// Whether the contract being changed was removed meanwhile, as on
    /// another device or by undo. Never for a new one.
    private var isGone: Bool {
        !isNew && model.ledger.projects[projectID]?.contracts.contains { $0.id == original.id } != true
    }

    /// Closes the sheet once its contract is removed: there's nothing left
    /// to save to.
    private func closeIfGone() {
        if isGone {
            dismiss()
        }
    }

    /// Keeps the contract, unless it was removed meanwhile, as on another
    /// device, or can't be kept.
    private func save() {
        if isGone {
            problem = "This contract was removed, perhaps on another device. Cancel, then add it again if it's still needed."
            return
        }
        do {
            try model.setContract(edited, ofProject: projectID, undoManager: undoManager)
            dismiss()
        } catch let failure as ContractError {
            problem = message(for: failure)
        } catch {
            problem = message(for: .invalid)
        }
    }

    private func remove() {
        model.removeContract(original.id, fromProject: projectID, undoManager: undoManager)
        dismiss()
    }

    private func message(for error: ContractError) -> String {
        switch error {
        case .invalid:
            "A contract needs some hours, and an end on or after its start."
        case .overlaps(let other):
            "That shares days with the contract for \(Format.days(other.days))."
        case .noProject:
            "This project was deleted."
        }
    }
}

#if DEBUG
#Preview("Change") {
    let model = PreviewData.model()
    return Group {
        if let project = model.ledger.projects[PreviewData.website], let contract = project.contract(on: model.today) {
            ContractSheet(model: model, projectID: project.id, contract: contract, isNew: false, undoManager: nil)
        }
    }
}

#Preview("New") {
    let model = PreviewData.model()
    return ContractSheet(
        model: model,
        projectID: PreviewData.mobileApp,
        contract: Contract.next(after: [], today: model.today),
        isNew: true,
        undoManager: nil
    )
}
#endif
