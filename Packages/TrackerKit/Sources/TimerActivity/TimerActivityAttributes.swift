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
        /// The project's name, or "Unassigned".
        public var project: String
        /// The project's color, such as "#4F7CAC".
        public var color: String
        /// The note, or else the tags.
        public var detail: String

        public init(start: Date, project: String, color: String, detail: String) {
            self.start = start
            self.project = project
            self.color = color
            self.detail = detail
        }

        /// The project's color, for drawing.
        public var tint: Color {
            let digits = color.hasPrefix("#") ? String(color.dropFirst()) : color
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
                return .gray
            }
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    }

    public init() {}
}
#endif
