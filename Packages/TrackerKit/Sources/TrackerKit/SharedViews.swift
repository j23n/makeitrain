import SwiftUI
import TrackerCore

// Small views shared by the Mac and iOS screens.

extension AppModel {
    /// Whether there's something to say about storage: it isn't ready,
    /// files are still downloading or can't be read, or something failed.
    public var hasStorageNotices: Bool {
        state != .ready || missingFiles > 0 || !issues.isEmpty || lastError != nil
    }
}

/// What's wrong with storage right now, if anything, a label for each
/// thing, as the menu bar's popover and Settings show them.
public struct StorageNotices: View {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        switch model.state {
        case .loading:
            Label("Loading…", systemImage: "hourglass")
        case .waitingForICloud:
            Label("Looking for data in iCloud…", systemImage: "icloud")
        case .iCloudUnavailable:
            Label("iCloud isn't available. Data is read-only.", systemImage: "icloud.slash")
            Button("Use Local Storage") {
                Task { try? await model.switchStorage(to: .local) }
            }
        case .ready:
            EmptyView()
        }
        if model.missingFiles > 0 {
            Label("Downloading \(model.missingFiles) files from iCloud…", systemImage: "icloud.and.arrow.down")
        }
        if !model.issues.isEmpty {
            Label(
                model.issues.count == 1 ? "A data file can't be read." : "\(model.issues.count) data files can't be read.",
                systemImage: "exclamationmark.triangle"
            )
            #if os(macOS)
                .help(model.issues.map(\.path).joined(separator: "\n"))
            #endif
        }
        if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
            #if os(macOS)
                .lineLimit(3)
            #endif
        }
    }
}

/// Lays its views out in rows, starting a new row when one is full.
public struct FlowLayout: Layout {
    var spacing: CGFloat

    public init(spacing: CGFloat = 4) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
