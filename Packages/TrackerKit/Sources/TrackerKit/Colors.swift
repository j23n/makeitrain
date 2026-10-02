import SwiftUI
import TrackerCore

extension Color {
    /// A color from a hex string such as "#4F7CAC". Gray if it can't be read.
    public init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Colors offered for projects.
public enum ProjectColors {
    public static let palette = [
        "#4F7CAC", "#C0504D", "#9BBB59", "#8064A2",
        "#F79646", "#4BACC6", "#D4A017", "#7F7F7F",
    ]

    /// The first palette color no live project uses yet, or the least used.
    public static func next(in ledger: Ledger) -> String {
        let used = ledger.projects.values.filter { !$0.isDeleted }.map(\.color)
        return palette.min { a, b in
            used.filter { $0 == a }.count < used.filter { $0 == b }.count
        } ?? palette[0]
    }

    /// A palette color's name, such as "Blue", for VoiceOver and tooltips;
    /// the hex string for a color that isn't in the palette.
    public static func name(of hex: String) -> String {
        names[hex.uppercased()] ?? hex
    }

    private static let names = [
        "#4F7CAC": "Blue", "#C0504D": "Red", "#9BBB59": "Green", "#8064A2": "Purple",
        "#F79646": "Orange", "#4BACC6": "Teal", "#D4A017": "Gold", "#7F7F7F": "Gray",
    ]
}

extension Ledger {
    /// The color of an entry's project, gray for none.
    public func color(ofProject projectID: UUID?) -> Color {
        projectID.flatMap { projects[$0] }.map { Color(hex: $0.color) } ?? .gray
    }
}
