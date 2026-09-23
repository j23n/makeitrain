import Foundation

/// A JSON value for `JSONWriter`.
enum JSON: Equatable {
    case string(String)
    case number(Int)
    case bool(Bool)
    case array([JSON])
    case object([String: JSON])

    var isScalar: Bool {
        switch self {
        case .string, .number, .bool: true
        case .array, .object: false
        }
    }
}

/// Writes the data files' JSON: keys sorted, two-space indents, lists of plain
/// values on one line, and a newline at the end.
///
/// The app writes JSON itself rather than with `JSONEncoder`, so the layout
/// can't change between OS versions and short lists stay on one line.
enum JSONWriter {
    static func data(_ value: JSON) -> Data {
        var text = ""
        write(value, indent: 0, into: &text)
        text += "\n"
        return Data(text.utf8)
    }

    private static func write(_ value: JSON, indent: Int, into text: inout String) {
        switch value {
        case .string(let string):
            writeString(string, into: &text)
        case .number(let number):
            text += String(number)
        case .bool(let bool):
            text += bool ? "true" : "false"
        case .array(let items) where items.isEmpty:
            text += "[]"
        case .array(let items) where items.allSatisfy(\.isScalar):
            text += "["
            for (index, item) in items.enumerated() {
                if index > 0 {
                    text += ", "
                }
                write(item, indent: indent, into: &text)
            }
            text += "]"
        case .array(let items):
            text += "[\n"
            for (index, item) in items.enumerated() {
                text += String(repeating: "  ", count: indent + 1)
                write(item, indent: indent + 1, into: &text)
                text += index < items.count - 1 ? ",\n" : "\n"
            }
            text += String(repeating: "  ", count: indent) + "]"
        case .object(let members) where members.isEmpty:
            text += "{}"
        case .object(let members):
            text += "{\n"
            let keys = members.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for (index, key) in keys.enumerated() {
                text += String(repeating: "  ", count: indent + 1)
                writeString(key, into: &text)
                text += ": "
                write(members[key]!, indent: indent + 1, into: &text)
                text += index < keys.count - 1 ? ",\n" : "\n"
            }
            text += String(repeating: "  ", count: indent) + "}"
        }
    }

    private static func writeString(_ string: String, into text: inout String) {
        text += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                text += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }
}
