import SwiftUI
import TrackerCore

/// A project's contracts in its settings, the latest first, each with its
/// days and its time left or used. Selecting one opens it in a
/// `ContractSheet` to change or remove; "New Contract…" opens a new one
/// there, following the project's latest.
///
/// `.form` lays it out as a section of a grouped Form, as the narrow
/// layout's settings sheet shows it; `.panel` as a tinted box in the wide
/// layout's settings column on the Mac and iPad.
public struct ContractList: View {
    public enum Layout: Sendable {
        case form
        case panel
    }

    let model: AppModel
    let project: Project
    let layout: Layout
    @State private var editing: Editing?
    @State private var removing: Contract?
    @Environment(\.undoManager) private var undoManager

    /// A contract open in the sheet.
    private struct Editing: Identifiable {
        let contract: Contract
        let isNew: Bool
        var id: UUID { contract.id }
    }

    public init(model: AppModel, project: Project, layout: Layout) {
        self.model = model
        self.project = project
        self.layout = layout
    }

    /// The project's contracts, the latest first.
    private var contracts: [Contract] {
        project.contracts.sorted { $0.start > $1.start }
    }

    public var body: some View {
        switch layout {
        case .form: formLayout
        case .panel: panelLayout
        }
    }

    /// The sheet and the question before removing. In a Form they go on
    /// one row, since a section passes what's put on it to every row.
    private func presentations<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $editing) { item in
                ContractSheet(model: model, projectID: project.id, contract: item.contract, isNew: item.isNew)
            }
            .confirmationDialog(
                "Remove the contract for \(removing.map { Format.days($0.days) } ?? "")?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible,
                presenting: removing
            ) { contract in
                Button("Remove", role: .destructive) {
                    model.removeContract(contract.id, fromProject: project.id, undoManager: undoManager)
                }
            }
    }

    // MARK: - Form

    private var formLayout: some View {
        Section {
            ForEach(contracts) { contract in
                Button {
                    open(contract)
                } label: {
                    HStack(spacing: 8) {
                        row(contract)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Remove", role: .destructive) { removing = contract }
                        .disabled(model.isReadOnly)
                }
                .contextMenu { menu(contract) }
            }
            presentations(
                Button("New Contract…", action: openNew)
                    .disabled(model.isReadOnly)
            )
        } header: {
            Text("Contracts")
        } footer: {
            Text(note)
        }
    }

    // MARK: - Panel

    private var panelLayout: some View {
        presentations(panelBox)
    }

    private var panelBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contracts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            if !contracts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(contracts.enumerated()), id: \.element.id) { index, contract in
                        HStack(spacing: 6) {
                            Button {
                                open(contract)
                            } label: {
                                row(contract)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Change or remove this contract")
                            Menu {
                                menu(contract)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(Theme.text3)
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .menuIndicatorHidden()
                            .fixedSize()
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("More for the contract for \(Format.days(contract.days))"))
                        }
                        .padding(.vertical, 7)
                        .contextMenu { menu(contract) }
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle().fill(Theme.accentLine.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                }
            }
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            Button("New Contract…", action: openNew)
                .buttonStyle(ChoiceButtonStyle(compact: true))
                .disabled(model.isReadOnly)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentFill.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accentLine.opacity(0.65)))
    }

    // MARK: - Parts

    /// A contract's days, and its time left while it runs, its time used
    /// once it's ended, or its hours before it starts.
    private func row(_ contract: Contract) -> some View {
        let status = model.status(of: contract, projectID: project.id)
        return VStack(alignment: .leading, spacing: 2) {
            Text(Format.days(contract.days))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            detail(status)
                .font(layout == .form ? .subheadline : .system(size: 12))
                .monospacedDigit()
        }
        .font(layout == .form ? .body : .system(size: 12.5, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detail(_ status: ContractStatus) -> some View {
        let hours = Format.hours(status.contract.hours)
        if !status.hasStarted {
            Text("\(hours), starts \(Format.monthDay(status.contract.start))")
                .foregroundStyle(Theme.text2)
        } else if status.hasEnded {
            Text("\(Format.duration(status.used)) of \(hours) used")
                .foregroundStyle(status.isOver ? Theme.overText : Theme.text2)
        } else {
            Text("\(Format.left(status)) of \(hours)")
                .foregroundStyle(status.leftColor ?? Theme.text2)
        }
    }

    @ViewBuilder
    private func menu(_ contract: Contract) -> some View {
        Button("Change…") { open(contract) }
        Button("Remove…", role: .destructive) { removing = contract }
            .disabled(model.isReadOnly)
    }

    private var note: String {
        contracts.isEmpty
            ? "Add the hours agreed for some days. Time on those days counts toward them."
            : "Time on a contract's days counts toward its hours."
    }

    private func open(_ contract: Contract) {
        editing = Editing(contract: contract, isNew: false)
    }

    /// Opens a contract after the project's latest, with its hours, length
    /// and alert, or 40 hours over this month for the first.
    private func openNew() {
        editing = Editing(contract: Contract.next(after: project.contracts, today: model.today), isNew: true)
    }
}

#if DEBUG
#Preview("Form") {
    let model = PreviewData.model()
    return Form {
        if let project = model.ledger.projects[PreviewData.website] {
            ContractList(model: model, project: project, layout: .form)
        }
    }
    .formStyle(.grouped)
    .frame(width: 390, height: 500)
}

#Preview("Panel") {
    let model = PreviewData.model()
    return Group {
        if let project = model.ledger.projects[PreviewData.website] {
            ContractList(model: model, project: project, layout: .panel)
                .padding()
        }
    }
    .frame(width: 360)
    .background(Theme.panel)
}
#endif
