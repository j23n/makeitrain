import SwiftUI
import TrackerCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A color written as red, green, blue and alpha from 0 to 1.
public struct RGBA: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// A color such as 0x4F7CAC.
    public init(_ hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// A color written as "#4F7CAC", or gray if it can't be read.
    public init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self.init(0x7F7F7F)
            return
        }
        self.init(value)
    }

    /// White, as a color made of only white and alpha.
    public static func white(_ alpha: Double) -> RGBA {
        RGBA(red: 1, green: 1, blue: 1, alpha: alpha)
    }

    /// The near-black ink of light mode, with alpha.
    public static func ink(_ alpha: Double) -> RGBA {
        RGBA(0x0F1218, alpha: alpha)
    }

    public func opacity(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Mixed with another color: 0 is this one, 1 the other.
    public func mixed(with other: RGBA, _ amount: Double) -> RGBA {
        RGBA(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount,
            alpha: alpha
        )
    }

    /// How light the color looks, from 0 to 1.
    public var lightness: Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }
}

extension Color {
    /// A color that's `light` in light mode and `dark` in dark mode,
    /// following the window's appearance.
    public init(light: RGBA, dark: RGBA) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let color = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        })
        #else
        self.init(uiColor: UIColor { traits in
            let color = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        })
        #endif
    }
}

/// The app's colors, in light and dark, as the designs set them. Times and
/// totals use the system font with digits of even width; only the command
/// line is monospaced.
public enum Theme {
    // Surfaces.
    /// Behind everything in a window.
    public static let background = Color(light: RGBA(0xF4F5F7), dark: RGBA(0x0E1015))
    /// Toolbars and title areas.
    public static let bar = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x14171D))
    /// Side panels and the area under a bar.
    public static let sunken = Color(light: RGBA(0xFAFAFB), dark: RGBA(0x121419))
    /// Panels, such as the corrections beside the week.
    public static let panel = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x14171D))
    /// Cards on a panel.
    public static let card = Color(light: RGBA(0xF6F7F9), dark: RGBA(0x181C23))
    /// Popovers and sheets that float over a window.
    public static let popover = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x171A21))
    /// Raised rows and buttons.
    public static let raised = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x1A1E26))
    /// Text fields and the calendar's canvas.
    public static let field = Color(light: RGBA(0xF4F5F7), dark: RGBA(0x0E1015))
    /// The week's canvas.
    public static let canvas = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x0E1015))
    /// A day of a month that has time.
    public static let cell = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x161A22))
    /// A weekend day of a month.
    public static let weekendCell = Color(light: RGBA(0xEFF1F4), dark: RGBA(0x121419))
    /// A day outside the month shown.
    public static let outsideCell = Color(light: RGBA(0xECEEF1), dark: RGBA(0x111318))
    /// The selected segment of a segmented control.
    public static let segment = Color(light: RGBA(0xFFFFFF), dark: RGBA.white(0.16))

    // Lines and fills.
    public static let line = Color(light: .ink(0.08), dark: .white(0.07))
    public static let strongLine = Color(light: .ink(0.15), dark: .white(0.13))
    public static let hourLine = Color(light: .ink(0.06), dark: .white(0.06))
    public static let fill = Color(light: .ink(0.05), dark: .white(0.06))
    public static let emptyBar = Color(light: .ink(0.08), dark: .white(0.08))

    // Text.
    public static let text = Color(light: RGBA(0x14171D), dark: RGBA(0xE9ECF2))
    public static let text2 = Color(light: RGBA(0x4B5363), dark: RGBA(0xA7AFBD))
    public static let text3 = Color(light: RGBA(0x687183), dark: RGBA(0x7D8696))
    /// Text that stands out a little less than `text`, such as notes.
    public static let text4 = Color(light: RGBA(0x2F3540), dark: RGBA(0xC9D0DC))

    // Accents.
    public static let accent = Color(light: RGBA(0x355BD6), dark: RGBA(0x9DB5FF))
    public static let accentFill = Color(light: RGBA(0x355BD6, alpha: 0.10), dark: RGBA(0x9DB5FF, alpha: 0.12))
    public static let accentLine = Color(light: RGBA(0x355BD6, alpha: 0.30), dark: RGBA(0x9DB5FF, alpha: 0.35))
    public static let link = Color(light: RGBA(0x2F55C8), dark: RGBA(0x9DB5FF))
    /// Tags, and issue references in particular.
    public static let tag = Color(light: RGBA(0x2F55C8), dark: RGBA(0xC3D1FF))
    /// A switch that's on.
    public static let on = Color(light: RGBA(0x355BD6), dark: RGBA(0x5B7FEB))
    public static let ok = Color(light: RGBA(0x1F7A4D), dark: RGBA(0x7FD1A3))
    public static let okFill = Color(light: RGBA(0x1F7A4D, alpha: 0.12), dark: RGBA(0x7FD1A3, alpha: 0.16))

    /// The running timer and the line at the current time.
    public static let now = Color(light: RGBA(0xE5484D), dark: RGBA(0xFF5C5C))
    /// Text on `now`.
    public static let nowText = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x14161B))

    // Corrections.
    public static let amber = Color(light: RGBA(0xD97706), dark: RGBA(0xF5A524))
    public static let amberText = Color(light: RGBA(0x9A4A07), dark: RGBA(0xF7D08A))
    public static let amberFill = Color(light: RGBA(0xD97706, alpha: 0.12), dark: RGBA(0xF5A524, alpha: 0.16))
    public static let amberWash = Color(light: RGBA(0xD97706, alpha: 0.06), dark: RGBA(0xF5A524, alpha: 0.07))
    public static let amberLine = Color(light: RGBA(0xD97706, alpha: 0.40), dark: RGBA(0xF5A524, alpha: 0.38))
    /// The stripes over time counted twice.
    public static let hatch = Color(light: RGBA(0xD97706, alpha: 0.40), dark: RGBA(0xF5A524, alpha: 0.55))
    /// The numbered markers of corrections.
    public static let marker = Color(light: RGBA(0xB45309), dark: RGBA(0xF5A524))
    public static let markerText = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x14161B))

    // Inverted, for the key that does what's suggested.
    public static let inverse = Color(light: RGBA(0x14171D), dark: RGBA(0xE9ECF2))
    public static let inverseText = Color(light: RGBA(0xFFFFFF), dark: RGBA(0x14161B))
    /// Key caps' borders.
    public static let key = Color(light: .ink(0.18), dark: .white(0.16))
    /// What a preview would add, drawn as an outline.
    public static let ghost = Color(light: RGBA(0x14171D, alpha: 0.35), dark: RGBA(0xE9ECF2, alpha: 0.45))
    /// The outline of the selected block.
    public static let selection = Color(light: RGBA(0x355BD6), dark: RGBA(0xE9ECF2))

    // Type.
    /// The command line's text: the one monospaced place.
    public static func commandFont(size: CGFloat = 15) -> Font {
        .system(size: size, design: .monospaced)
    }

    /// A small heading over a group, in sentence case.
    public static let heading = Font.subheadline.weight(.semibold)
}

/// The colors drawn for a project's color: lighter on dark backgrounds, and
/// darker on light ones where the color itself is light.
public struct ProjectTint: Hashable, Sendable {
    public let base: RGBA

    public init(hex: String) {
        base = RGBA(hex: hex)
    }

    /// Gray, for entries without a project.
    public static let none = ProjectTint(hex: "#7F7F7F")

    private var lightInk: RGBA {
        base.lightness > 0.55 ? base.mixed(with: RGBA(0x000000), 0.18) : base
    }

    private var darkInk: RGBA {
        base.mixed(with: RGBA(0xFFFFFF), 0.3)
    }

    /// Text, dots and outlines.
    public var ink: Color {
        Color(light: lightInk, dark: darkInk)
    }

    /// A block's fill.
    public var fill: Color {
        Color(light: base.opacity(0.14), dark: base.opacity(0.30))
    }

    /// A selected or running block's fill.
    public var strongFill: Color {
        Color(light: base.opacity(0.24), dark: base.opacity(0.44))
    }

    /// A faint fill, as behind a preview.
    public var softFill: Color {
        Color(light: base.opacity(0.08), dark: base.opacity(0.16))
    }

    /// Bars in charts.
    public var bar: Color {
        Color(light: base.opacity(0.85), dark: darkInk.opacity(0.85))
    }
}

extension Ledger {
    /// The tint of an entry's project, gray for none.
    public func tint(ofProject projectID: UUID?) -> ProjectTint {
        projectID.flatMap { projects[$0] }.map { ProjectTint(hex: $0.color) } ?? .none
    }
}
