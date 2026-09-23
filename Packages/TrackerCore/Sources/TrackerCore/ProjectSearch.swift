import Foundation

/// Finding a project from what's typed into a picker. Each word typed has to
/// appear in the client's or the project's name, ignoring case and accents,
/// so "web", "site" and "acme web" all find "Acme › Website redesign".
public enum ProjectSearch {
    /// The words typed, folded for comparing.
    public static func terms(_ query: String) -> [String] {
        words(fold(query))
    }

    /// Whether a picker should offer "No Project" for what's typed: when
    /// nothing is typed, or when each word starts a word of "No Project" or
    /// "Unassigned".
    public static func matchesNoProject(_ query: String) -> Bool {
        let names = ["no", "project", "unassigned"]
        return terms(query).allSatisfy { term in names.contains { $0.hasPrefix(term) } }
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

extension Ledger {
    /// The projects a picker offers for what's typed: the best matches
    /// first, and otherwise in picker order, live projects grouped by client.
    /// `including` adds a project pickers don't offer, such as the archived
    /// project an entry already has, when it matches too.
    public func pickerProjects(matching query: String, including extra: UUID? = nil) -> [Project] {
        var candidates = pickerProjects()
        if let extra, let project = projects[extra], !candidates.contains(where: { $0.id == extra }) {
            candidates.append(project)
        }
        let terms = ProjectSearch.terms(query)
        guard !terms.isEmpty else { return candidates }
        var matches: [(rank: Int, index: Int, project: Project)] = []
        for (index, project) in candidates.enumerated() {
            let clientName = client(forProject: project.id)?.name ?? ""
            if let rank = ProjectSearch.rank(terms, project: project.name, client: clientName) {
                matches.append((rank, index, project))
            }
        }
        return matches
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map { $0.project }
    }
}
