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

/// Colors offered for projects. The palette lives in TrackerCore, so the
/// command line can name colors too.
public enum ProjectColors {
    public static var palette: [String] { Palette.colors }

    /// The first palette color no live project uses yet, or the least used.
    public static func next(in ledger: Ledger) -> String {
        Palette.next(in: ledger)
    }

    /// A palette color's name, such as "Blue", for VoiceOver and tooltips;
    /// the hex string for a color that isn't in the palette.
    public static func name(of hex: String) -> String {
        Palette.name(of: hex)
    }
}

extension Ledger {
    /// The color of an entry's project, gray for none.
    public func color(ofProject projectID: UUID?) -> Color {
        projectID.flatMap { projects[$0] }.map { Color(hex: $0.color) } ?? .gray
    }
}
