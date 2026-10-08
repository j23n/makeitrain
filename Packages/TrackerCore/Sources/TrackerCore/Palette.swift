import Foundation

/// The colors offered for projects, as hex strings, and their names.
public enum Palette {
    public static let colors = names.map(\.hex)

    /// The first color no live project uses yet, or the least used.
    public static func next(in ledger: Ledger) -> String {
        let used = ledger.projects.values.filter { !$0.isDeleted }.map { $0.color.uppercased() }
        return colors.min { a, b in
            used.filter { $0 == a }.count < used.filter { $0 == b }.count
        } ?? colors[0]
    }

    /// A color's name, such as "Blue", or the hex string for a color that
    /// isn't in the palette.
    public static func name(of hex: String) -> String {
        names.first { $0.hex == hex.uppercased() }?.name ?? hex
    }

    /// The color a name such as "teal" stands for, ignoring case, or a hex
    /// color written as "#4bacc6" or "4BACC6", in capitals with a "#". Nil
    /// for anything else.
    public static func color(named text: String) -> String? {
        let typed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let named = names.first(where: { $0.name.lowercased() == typed || $0.aliases.contains(typed) }) {
            return named.hex
        }
        let digits = typed.hasPrefix("#") ? String(typed.dropFirst()) : typed
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.uppercased()
    }

    private static let names: [(hex: String, name: String, aliases: [String])] = [
        ("#4F7CAC", "Blue", []),
        ("#C0504D", "Red", []),
        ("#9BBB59", "Green", []),
        ("#8064A2", "Purple", ["violet"]),
        ("#F79646", "Orange", []),
        ("#4BACC6", "Teal", ["cyan"]),
        ("#D4A017", "Gold", ["yellow"]),
        ("#7F7F7F", "Gray", ["grey"]),
    ]
}
