#if os(iOS)
import ActivityKit
import SwiftUI

/// The running timer as a Live Activity, on the Lock Screen and in the
/// Dynamic Island. The app starts, updates and ends it; the widget
/// extension draws it. Both link this, so they agree on what's in it.
public struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// When the timer started, to count up from.
        public var start: Date
        /// The timer's entry, so a button stops only that one.
        public var entryID: UUID?
        /// The project's name, or "Unassigned".
        public var project: String
        /// The project's color, such as "#4F7CAC".
        public var color: String
        /// The note, or else the tags.
        public var detail: String
        /// When the timer stopped, once it has: the activity then stays a
        /// few minutes to continue it.
        public var end: Date?
        /// The line that starts the timer's project, tags and note again,
        /// for Continue, when one reads back as them.
        public var line: String?
        /// When the timer counts as left running: the activity goes stale
        /// then, and asks whether it's still running.
        public var ranLong: Date?
        /// When a timer left running likely ended, as the day usually
        /// ends, to stop it there.
        public var likelyEnd: Date?
        /// The latest other entries, to switch to.
        public var switchTo: [Shortcut]?

        public init(
            start: Date,
            entryID: UUID? = nil,
            project: String,
            color: String,
            detail: String,
            end: Date? = nil,
            line: String? = nil,
            ranLong: Date? = nil,
            likelyEnd: Date? = nil,
            switchTo: [Shortcut] = []
        ) {
            self.start = start
            self.entryID = entryID
            self.project = project
            self.color = color
            self.detail = detail
            self.end = end
            self.line = line
            self.ranLong = ranLong
            self.likelyEnd = likelyEnd
            self.switchTo = switchTo
        }

        /// The project's color, for drawing.
        public var tint: Color {
            TimerActivityAttributes.color(color)
        }

        /// The project's color made lighter, for drawing on the activity's
        /// dark background.
        public var lightTint: Color {
            TimerActivityAttributes.color(color, lightened: 0.3)
        }
    }

    /// Another entry to switch to: its project's name, or its note without
    /// one, its project's color, and the line that starts it.
    public struct Shortcut: Codable, Hashable, Sendable {
        public var title: String
        public var color: String
        public var line: String

        public init(title: String, color: String, line: String) {
            self.title = title
            self.color = color
            self.line = line
        }

        /// The project's color made lighter, as `ContentState.lightTint`.
        public var lightTint: Color {
            TimerActivityAttributes.color(color, lightened: 0.3)
        }
    }

    public init() {}

    /// A color such as "#4F7CAC", mixed with `lightened` of white; gray
    /// when it can't be read.
    static func color(_ hex: String, lightened: Double = 0) -> Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return .gray
        }
        func channel(_ shift: UInt32) -> Double {
            let base = Double((value >> shift) & 0xFF) / 255
            return base + (1 - base) * lightened
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }
}
#endif
