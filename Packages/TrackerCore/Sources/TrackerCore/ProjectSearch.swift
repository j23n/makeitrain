import Foundation

/// Finding a project from what's typed, on the command line or in the
/// projects list's filter. Each word typed has to appear in the client's or
/// the project's name, ignoring case and accents, so "web", "site" and
/// "acme web" all find "Acme › Website redesign".
public enum ProjectSearch {
    /// The words typed, folded for comparing.
    public static func terms(_ query: String) -> [String] {
        words(fold(query))
    }

    /// Whether a project shows in the projects list for what's typed in its
    /// filter: each word appears somewhere in the client's or the project's
    /// name. Every project does while nothing is typed.
    public static func matches(_ query: String, project: String, client: String) -> Bool {
        rank(terms(query), project: project, client: client) != nil
    }

    /// How well a project matches the words typed, best first: 0 when its
    /// name starts with them, 1 when each starts a word of the client's or
    /// the project's name, 2 when each appears anywhere in them. Nil when a
    /// word doesn't appear.
    static func rank(_ terms: [String], project: String, client: String) -> Int? {
        guard !terms.isEmpty else { return 0 }
        let name = fold(project)
        let clientName = fold(client)
        if name.hasPrefix(terms.joined(separator: " ")) {
            return 0
        }
        let nameWords = words(name) + words(clientName)
        if terms.allSatisfy({ term in nameWords.contains { $0.hasPrefix(term) } }) {
            return 1
        }
        let text = clientName + " " + name
        if terms.allSatisfy({ text.contains($0) }) {
            return 2
        }
        return nil
    }

    /// Lowercase and without accents, so "Café" matches "cafe".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Runs of letters and digits.
    static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
