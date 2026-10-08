import SwiftUI
import TrackerKit

/// The column at the right of a wide window: the command line while it's
/// used, the selected entry, what needs correcting, or a screen's own panel,
/// such as a month's statement.
enum Sidebar {
    static let width: CGFloat = 380
}

private struct CommandSidebarShownKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the sidebar shows the command line, so a screen leaves its
    /// own panel out meanwhile.
    var commandSidebarShown: Bool {
        get { self[CommandSidebarShownKey.self] }
        set { self[CommandSidebarShownKey.self] = newValue }
    }
}

extension View {
    /// Lays a view out as the sidebar: its width, the panel's background
    /// and a line along its left.
    func sidebarColumn() -> some View {
        frame(width: Sidebar.width)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.panel)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.line).frame(width: 1)
            }
    }
}

/// A sidebar's title, with a detail such as a duration, and a button to
/// close it.
struct SidebarTitle: View {
    let title: String
    var detail: String?
    var close: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.fill))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel(Text("Close"))
            }
        }
    }
}
