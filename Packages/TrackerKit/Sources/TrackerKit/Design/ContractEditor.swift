import SwiftUI
import TrackerCore

/// A project's contracts in its settings: the hours, days and alert of the
/// one that holds today, or else the next to start, the others under it,
/// and buttons to add the next one or remove one. Each change is kept as
/// it's made. It sits in a project's settings, at touch size with `touch`
/// set; in a Form's section, `inForm` leaves the hours field to the Form.
public struct ContractEditor: View {
    let model: AppModel
    let project: Project
    let inForm: Bool
    let touch: Bool
    @State private var error: ContractError?
    @Environment(\.undoManager) private var undoManager

    public init(model: AppModel, project: Project, inForm: Bool = false, touch: Bool = false) {
        self.model = model
        self.project = project
        self.inForm = inForm
        self.touch = touch
    }

    private var contract: Contract? {
        project.contract(on: model.today)
    }

    public var body: some View {
        if let contract {
            LabeledContent("Hours") {
                TextField("Hours", value: Binding(
                    get: { contract.hours },
                    set: { hours in change(contract) { $0.hours = hours } }
                ), format: .number)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .modifier(HoursField(inForm: inForm))
            }
            DatePicker("From", selection: day(of: contract, \.start), displayedComponents: .date)
            DatePicker("To", selection: day(of: contract, \.end), displayedComponents: .date)
            Stepper(value: Binding(
                get: { contract.alertsAt },
                set: { hours in
                    change(contract) { $0.alertHours = hours == Contract.defaultAlertHours(for: $0.hours) ? nil : hours }
                }
            ), in: 0...max(1, contract.hours)) {
                Text(contract.alertsAt > 0 ? "Alert at \(Format.hours(contract.alertsAt)) left" : "No alert")
                    .monospacedDigit()
            }
            if let error {
                Text(message(for: error))
                    .font(.system(size: touch ? 14 : 12))
                    .foregroundStyle(Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(others(than: contract)) { other in
                otherRow(other)
            }
            HStack(spacing: 12) {
                Button("Add the Next Contract", action: addNext)
                Spacer(minLength: 0)
                Button("Remove", role: .destructive) {
                    error = nil
                    model.removeContract(contract.id, fromProject: project.id, undoManager: undoManager)
                }
            }
            #if os(iOS)
            .buttonStyle(.borderless)
            #endif
        } else {
            Button("Add a Contract", action: addNext)
            ForEach(project.earlierContracts(before: model.today)) { other in
                otherRow(other)
            }
        }
    }

    /// The project's other contracts, the latest first.
    private func others(than contract: Contract) -> [Contract] {
        project.contracts.filter { $0.id != contract.id }.sorted { $0.start > $1.start }
    }

    /// Another contract: its days, and its time used of its hours.
    private func otherRow(_ other: Contract) -> some View {
        let status = model.status(of: other, projectID: project.id)
        return HStack(spacing: 8) {
            Text(Format.days(other.days))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(status.hasStarted ? "\(Format.duration(status.used)) of \(Format.hours(other.hours))" : Format.hours(other.hours))
                .monospacedDigit()
                .foregroundStyle(status.isOver ? Theme.overText : Theme.text2)
            Button {
                error = nil
                model.removeContract(other.id, fromProject: project.id, undoManager: undoManager)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: touch ? 13 : 10, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .frame(width: touch ? 44 : nil, height: touch ? 44 : nil)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove the contract for \(Format.days(other.days))"))
        }
        .font(.system(size: touch ? 15 : 12.5))
    }

    /// A picker's date for one of the contract's days, which changes it.
    private func day(of contract: Contract, _ keyPath: WritableKeyPath<Contract, LocalDate>) -> Binding<Date> {
        Binding(
            get: { contract[keyPath: keyPath].pickerDate },
            set: { date in change(contract) { $0[keyPath: keyPath] = LocalDate(pickerDate: date) } }
        )
    }

    /// Keeps a change to a contract, or shows why it can't be kept.
    private func change(_ contract: Contract, _ update: (inout Contract) -> Void) {
        var changed = contract
        update(&changed)
        guard changed != contract else { return }
        save(changed)
    }

    /// Adds a contract after the project's latest, with its hours, length
    /// and alert, or 40 hours over this month for the first.
    private func addNext() {
        save(Contract.next(after: project.contracts, today: model.today))
    }

    private func save(_ contract: Contract) {
        do {
            try model.setContract(contract, ofProject: project.id, undoManager: undoManager)
            error = nil
        } catch let failure as ContractError {
            error = failure
        } catch {
            self.error = .invalid
        }
    }

    /// A rounded border and a fixed width for the hours, except in a Form,
    /// which has its own.
    private struct HoursField: ViewModifier {
        let inForm: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if inForm {
                content
            } else {
                content
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
        }
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
#Preview("Contract editor") {
    let model = PreviewData.model()
    return Form {
        if let project = model.ledger.projects[PreviewData.mobileApp] {
            Section("Contract") {
                ContractEditor(model: model, project: project, inForm: true)
            }
        }
    }
    .frame(width: 380, height: 420)
}
#endif
