import SwiftUI
import TrackerCore
import TrackerKit

/// Entries in a short list, as "find" and Down show them.
public struct EntryList: View {
    let model: AppModel
    let entries: [ResolvedEntry]

    public init(model: AppModel, entries: [ResolvedEntry]) {
        self.model = model
        self.entries = entries
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
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
            }
        }
        .padding(.vertical, 4)
    }

    private func times(_ entry: ResolvedEntry) -> String {
        let zone = entry.entry.timeZone
        let day = entry.entry.day == model.today ? "" : Format.monthDay(entry.entry.day) + " "
        let end = entry.end.map { Format.time($0, zone: zone) } ?? "now"
        return day + Format.time(entry.start, zone: zone) + "–" + end
    }
}
