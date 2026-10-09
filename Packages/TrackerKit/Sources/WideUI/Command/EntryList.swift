import SwiftUI
import TrackerCore
import TrackerKit

/// Entries in a short list, as "find" and Down show them. With `select`,
/// clicking one picks it.
public struct EntryList: View {
    let model: AppModel
    let entries: [ResolvedEntry]
    var select: ((ResolvedEntry) -> Void)?

    public init(model: AppModel, entries: [ResolvedEntry], select: ((ResolvedEntry) -> Void)? = nil) {
        self.model = model
        self.entries = entries
        self.select = select
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                if let select {
                    Button {
                        select(entry)
                    } label: {
                        row(entry)
                    }
                    .buttonStyle(.plain)
                } else {
                    row(entry)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func row(_ entry: ResolvedEntry) -> some View {
        HStack(spacing: 10) {
            Text(times(entry))
                .monospacedDigit()
                .foregroundStyle(Theme.text2)
                .frame(width: 110, alignment: .leading)
            ProjectName(ledger: model.ledger, projectID: entry.entry.projectID)
                .fixedSize()
            Text(([entry.entry.note] + entry.entry.tags).filter { !$0.isEmpty }.joined(separator: " · "))
                .foregroundStyle(Theme.text4)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(Format.duration(model.duration(of: entry)))
                .monospacedDigit()
                .foregroundStyle(entry.isRunning ? Theme.now : Theme.text2)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 26)
        .contentShape(Rectangle())
    }

    private func times(_ entry: ResolvedEntry) -> String {
        let zone = entry.entry.timeZone
        let day = entry.entry.day == model.today ? "" : Format.monthDay(entry.entry.day) + " "
        return day + Format.span(entry.start, entry.end, zone: zone)
    }
}
