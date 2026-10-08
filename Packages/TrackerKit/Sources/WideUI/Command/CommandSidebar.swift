import SwiftUI
import TrackerCore
import TrackerKit

/// The command line's sidebar, open while the line in the top bar is used,
/// as the iPhone's command sheet: what Return would do with a button for it
/// and for what the line could also mean, what "find" turned up, and words
/// to add to the line.
struct CommandSidebar: View {
    let line: CommandLineModel
    /// Runs the line, or with `alternate` what it could also mean.
    let submit: (_ alternate: Bool) -> Void
    /// Puts the keyboard back in the command line.
    let focus: () -> Void
    /// Clears the line and closes the sidebar.
    let close: () -> Void
    /// Shows an entry on its week, selected.
    let show: (ResolvedEntry) -> Void

    private var model: AppModel { line.model }

    private var finds: Bool {
        if case .find? = line.reading.primary { true } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarTitle(title: "Command line", close: close)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if finds {
                        found
                    } else if !line.text.isEmpty || line.message != nil {
                        CommandPreviewView(line: line, showsKey: false)
                            .font(.system(size: 13.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        actions
                    }
                    if line.showsToday {
                        entries("Today", Array(line.todaysEntries.prefix(12)))
                    }
                    chips
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            keys
        }
        .sidebarColumn()
    }

    /// The button for what Return does, and one for what the line could
    /// also mean, such as logging it as done.
    @ViewBuilder
    private var actions: some View {
        if let command = line.reading.primary, line.preview != nil {
            VStack(spacing: 8) {
                Button {
                    submit(false)
                } label: {
                    HStack(spacing: 10) {
                        Text(CommandText.verb(command, running: model.running))
                            .font(.system(size: 13.5, weight: .semibold))
                        KeyCap("⏎", onInverse: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .foregroundStyle(Theme.inverseText)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.inverse))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(model.isReadOnly)
                if let alternate = line.reading.alternate {
                    Button {
                        submit(true)
                    } label: {
                        HStack(spacing: 10) {
                            Text(CommandText.title(alternate, running: model.running, now: model.environment.now(), zone: model.environment.timeZone()))
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            KeyCap("⌥⏎")
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(Theme.text)
                        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.strongLine))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isReadOnly)
                }
            }
        }
    }

    /// What "find" turned up, the latest first. Clicking one shows its week.
    @ViewBuilder
    private var found: some View {
        if line.found.isEmpty {
            Text(line.text.split(separator: " ").count > 1 ? "Nothing found." : "Type what to find.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
        } else {
            entries("Found", Array(line.found.prefix(20)))
        }
    }

    private func entries(_ title: String, _ entries: [ResolvedEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
            EntryList(model: model, entries: entries, select: show)
                .padding(.horizontal, -14)
        }
    }

    /// Words to add to the line, or, with nothing typed, the lines run
    /// lately.
    @ViewBuilder
    private var chips: some View {
        let chips = line.chips
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(line.text.isEmpty ? "Run again" : "Add to the line")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                FlowLayout(spacing: 6) {
                    ForEach(chips) { chip in
                        Button {
                            line.apply(chip)
                            focus()
                        } label: {
                            ChipLabel(title: chip.title, tint: chip.tint, isTag: chip.isTag, isHighlighted: chip.isHighlighted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if line.text.isEmpty, !line.showsToday {
            Text("Type a project to start its timer, or add times to log them.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keys: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                KeyCap("⏎")
                Text("run")
            }
            HStack(spacing: 5) {
                KeyCap("⇥")
                Text("add")
            }
            HStack(spacing: 5) {
                KeyCap("↑")
                KeyCap("↓")
                Text("earlier")
            }
            HStack(spacing: 5) {
                KeyCap("esc")
                Text("clear")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.text2)
        .lineLimit(1)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}
