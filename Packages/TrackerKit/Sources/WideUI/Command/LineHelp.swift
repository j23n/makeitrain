import SwiftUI
import TrackerCore
import TrackerKit

/// What could replace the word being typed, as a row of chips: Tab takes
/// the highlighted one, ↑ and ↓ move the highlight, and a click takes any.
public struct SuggestionStrip: View {
    let suggestions: [LineSuggestion]
    let highlighted: Int
    let ledger: Ledger
    var showsKeys = true
    let accept: (Int) -> Void

    public init(suggestions: [LineSuggestion], highlighted: Int, ledger: Ledger, showsKeys: Bool = true, accept: @escaping (Int) -> Void) {
        self.suggestions = suggestions
        self.highlighted = highlighted
        self.ledger = ledger
        self.showsKeys = showsKeys
        self.accept = accept
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        accept(index)
                    } label: {
                        chip(suggestion, highlighted: index == highlighted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(suggestion.detail.isEmpty ? suggestion.title : "\(suggestion.title), \(suggestion.detail)"))
                }
            }
        }
    }

    private func chip(_ suggestion: LineSuggestion, highlighted: Bool) -> some View {
        HStack(spacing: 5) {
            switch suggestion.kind {
            case let .project(id):
                TintDot(ledger.tint(ofProject: id), size: 7)
            case let .color(hex):
                TintDot(ProjectTint(hex: hex), size: 7)
            default:
                EmptyView()
            }
            Text(suggestion.title)
                .foregroundStyle(color(of: suggestion.kind))
            if !suggestion.detail.isEmpty {
                Text(suggestion.detail)
                    .foregroundStyle(Theme.text3)
            }
            if highlighted, showsKeys {
                KeyCap("⇥")
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(highlighted ? Theme.accentFill : Theme.fill))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(highlighted ? Theme.accentLine : Color.clear))
        .contentShape(Rectangle())
    }

    private func color(of kind: CommandToken.Kind) -> Color {
        switch kind {
        case .tag: Theme.tag
        case .time: Theme.amberText
        case .keyword: Theme.accent
        default: Theme.text
        }
    }
}

/// What an entry's line reads as, part by part: its day, times, project,
/// tags and note. A part the line leaves out shows as what could go there,
/// and a line that isn't an entry says why.
public struct EntryLineGuide: View {
    let model: AppModel
    let line: EntryLineModel

    public init(model: AppModel, line: EntryLineModel) {
        self.model = model
        self.line = line
    }

    public var body: some View {
        if let parts = line.parts {
            HStack(spacing: 6) {
                Text(Format.day(parts.start.local(in: parts.zone).date))
                separator
                Text(times(parts))
                    .monospacedDigit()
                separator
                if let projectID = parts.draft.projectID {
                    HStack(spacing: 4) {
                        TintDot(model.ledger.tint(ofProject: projectID), size: 7)
                        Text(model.ledger.projectTitle(projectID))
                    }
                } else {
                    placeholder("project")
                }
                separator
                if parts.draft.tags.isEmpty {
                    placeholder("#tag")
                } else {
                    Text(parts.draft.tags.map(Tags.typed).joined(separator: " "))
                        .foregroundStyle(Theme.tag)
                }
                separator
                if parts.draft.note.isEmpty {
                    placeholder("note")
                } else {
                    Text(parts.draft.note)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            .lineLimit(1)
        } else if let problem = line.problem {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Theme.amber)
                Text(problem)
                    .foregroundStyle(line.refused ? Theme.amberText : Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12))
        }
    }

    private var separator: some View {
        Text("·").foregroundStyle(Theme.text3)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.text3)
    }

    /// "13:30–16:30, 3:00", or "from 13:30" while it runs.
    private func times(_ parts: EntryLineParts) -> String {
        let start = Format.time(parts.start, zone: parts.zone)
        guard let end = parts.end else { return "from \(start)" }
        return "\(start)–\(Format.time(end, zone: parts.zone)), \(Format.duration(parts.start.distance(to: end)))"
    }
}

/// Something to add to a line, as a button's label: outlined, with a
/// project's color, and highlighted with ⇥ when Tab takes it.
struct ChipLabel: View {
    let title: String
    var tint: ProjectTint?
    var isTag = false
    var isHighlighted = false

    var body: some View {
        HStack(spacing: 6) {
            if let tint {
                TintDot(tint, size: 7)
            }
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            if isHighlighted {
                KeyCap("⇥")
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(isTag ? Theme.tag : Theme.text)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(isHighlighted ? Theme.accentFill : Color.clear))
        .overlay(Capsule().strokeBorder(isHighlighted ? Theme.accentLine : Theme.strongLine))
        .contentShape(Capsule())
        .frame(maxWidth: Sidebar.width - 48, alignment: .leading)
    }
}

extension LineSuggestion {
    /// The color of the project or palette color it names, if it names one.
    func tint(in ledger: Ledger) -> ProjectTint? {
        switch kind {
        case let .project(id):
            ledger.tint(ofProject: id)
        case let .color(hex):
            ProjectTint(hex: hex)
        default:
            nil
        }
    }

    /// What a chip for it says: its title, and its detail after a dot.
    var chipTitle: String {
        detail.isEmpty ? title : "\(title) · \(detail)"
    }
}
