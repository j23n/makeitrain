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
///
/// Each row presents its own sheet and question, so they work while the
/// other rows of a long Form are scrolled away and not loaded.
public struct ContractList: View {
    public enum Layout: Sendable {
        case form
        case panel
    }

    let model: AppModel
    let project: Project
    let layout: Layout

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

    // MARK: - Form

    private var formLayout: some View {
        Section {
            ForEach(contracts) { contract in
                ContractRow(model: model, project: project, contract: contract, layout: .form, isFirst: false)
            }
            NewContractButton(model: model, project: project, layout: .form)
        } header: {
            Text("Contracts")
        } footer: {
            Text(note)
        }
    }

    // MARK: - Panel

    private var panelLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contracts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            if !contracts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(contracts.enumerated()), id: \.element.id) { index, contract in
                        ContractRow(model: model, project: project, contract: contract, layout: .panel, isFirst: index == 0)
                    }
                }
            }
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            NewContractButton(model: model, project: project, layout: .panel)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentFill.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accentLine.opacity(0.65)))
    }

    private var note: String {
        contracts.isEmpty
            ? "Add the hours agreed for some days. Time on those days counts toward them."
            : "Time on a contract's days counts toward its hours."
    }
}

/// "New Contract…", which opens a contract after the project's latest,
/// with its hours, length and alert, or 40 hours over this month for the
/// first.
private struct NewContractButton: View {
    let model: AppModel
    let project: Project
    let layout: ContractList.Layout
    @State private var contract: Contract?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        styled(Button("New Contract…") {
            contract = Contract.next(after: project.contracts, today: model.today)
        })
        .disabled(model.isReadOnly)
        .sheet(item: $contract) { contract in
            ContractSheet(model: model, projectID: project.id, contract: contract, isNew: true, undoManager: undoManager)
        }
    }

    @ViewBuilder
    private func styled(_ button: Button<Text>) -> some View {
        if layout == .panel {
            button.buttonStyle(ChoiceButtonStyle(compact: true))
        } else {
            button
        }
    }
}

/// A contract in the list: its days and its time, opening it in the
/// sheet, with a menu to change or remove it.
private struct ContractRow: View {
    let model: AppModel
    let project: Project
    let contract: Contract
    let layout: ContractList.Layout
    /// Whether it's the panel's first row, which has no line above it.
    let isFirst: Bool
    @State private var editing = false
    @State private var removing = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        content
            .sheet(isPresented: $editing) {
                ContractSheet(model: model, projectID: project.id, contract: contract, isNew: false, undoManager: undoManager)
            }
            .confirmationDialog("Remove the contract for \(Format.days(contract.days))?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.removeContract(contract.id, fromProject: project.id, undoManager: undoManager)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .form: formRow
        case .panel: panelRow
        }
    }

    /// In the form: the row with a chevron, and a swipe to remove it.
    private var formRow: some View {
        Button {
            editing = true
        } label: {
            HStack(spacing: 8) {
                summary
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Remove", role: .destructive) { removing = true }
                .disabled(model.isReadOnly)
        }
        .contextMenu { menu }
    }

    /// In the panel: the row, and a menu at its end.
    private var panelRow: some View {
        HStack(spacing: 6) {
            Button {
                editing = true
            } label: {
                summary
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change or remove this contract")
            moreMenu
        }
        .padding(.vertical, 7)
        .contextMenu { menu }
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(Theme.accentLine.opacity(0.6)).frame(height: 1)
            }
        }
    }

    private var moreMenu: some View {
        let label = Image(systemName: "ellipsis")
            .foregroundStyle(Theme.text3)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        return Menu {
            menu
        } label: {
            label
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More for the contract for \(Format.days(contract.days))"))
    }

    @ViewBuilder
    private var menu: some View {
        Button("Change…") { editing = true }
        Button("Remove…", role: .destructive) { removing = true }
            .disabled(model.isReadOnly)
    }

    /// The days, and the time left while it runs, the time used once it's
    /// ended, or the hours before it starts.
    private var summary: some View {
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
