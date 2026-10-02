import Foundation

/// GitHub repositories of a project, and the issues and pull requests its
/// tags refer to.
///
/// A tag like `#123` refers to issue or pull request 123 in the project's
/// first repository. `api#123` refers to #123 in the project's repository
/// named `api`, and `owner/repo#123` to #123 in any repository, as GitHub
/// writes references. A slash before the "#", as in `api/#123`, reads the
/// same. Opening an issue's address shows the pull request when the number
/// is one, so a tag doesn't need to say which it is.
public enum GitHub {
    /// A repository, such as github.com/j23n/makeitrain.
    public struct Repository: Hashable, Sendable {
        /// The server, such as "github.com" or a GitHub Enterprise host.
        public var host: String
        public var owner: String
        public var name: String

        public init(host: String = "github.com", owner: String, name: String) {
            self.host = host
            self.owner = owner
            self.name = name
        }

        /// Reads a repository written as "owner/repo" or "github.com/owner/repo",
        /// as a web address such as "https://github.com/owner/repo" or an
        /// address of one of its pages, or as a clone address such as
        /// "git@github.com:owner/repo.git". Nil if it's none of these.
        public init?(_ text: String) {
            var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var host = "github.com"
            if let scheme = rest.range(of: "://") {
                rest = String(rest[scheme.upperBound...])
                guard let slash = rest.firstIndex(of: "/") else { return nil }
                host = String(rest[..<slash])
                rest = String(rest[rest.index(after: slash)...])
            } else if rest.hasPrefix("git@"), let colon = rest.firstIndex(of: ":") {
                host = String(rest[rest.index(rest.startIndex, offsetBy: 4)..<colon])
                rest = String(rest[rest.index(after: colon)...])
            } else if let first = rest.split(separator: "/").first,
                      first.contains("."), rest.split(separator: "/").count >= 3 || first.lowercased() == "github.com" {
                host = String(first)
                rest = rest.split(separator: "/").dropFirst().joined(separator: "/")
            }
            if let at = host.lastIndex(of: "@") {
                host = String(host[host.index(after: at)...])
            }
            let parts = rest.split(separator: "/").map(String.init)
            guard parts.count >= 2, !host.isEmpty, !host.contains(" ") else { return nil }
            let owner = parts[0]
            var name = parts[1]
            if name.lowercased().hasSuffix(".git") {
                name = String(name.dropLast(4))
            }
            guard Self.isName(owner), Self.isName(name) else { return nil }
            self.init(host: host.lowercased(), owner: owner, name: name)
        }

        /// Whether `text` can be an owner's or a repository's name.
        static func isName(_ text: some StringProtocol) -> Bool {
            !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
        }

        /// The repository's web address, such as
        /// "https://github.com/j23n/makeitrain", which is how projects store it.
        public var address: String {
            "https://\(host)/\(owner)/\(name)"
        }

        /// How the repository is shown: "j23n/makeitrain", with the host in
        /// front when it isn't github.com.
        public var title: String {
            host == "github.com" ? "\(owner)/\(name)" : "\(host)/\(owner)/\(name)"
        }
    }

    /// What a tag like `#123`, `api#123` or `owner/repo#123` refers to, or
    /// the same with a slash before the "#", as in `api/#123`.
    public struct Reference: Hashable, Sendable {
        /// The repository written before "#", without the slash: a
        /// repository's name, or its owner and name. Nil for the project's
        /// first repository.
        public var repository: String?
        /// The issue or pull request number.
        public var number: Int

        /// Nil unless the whole tag is a reference.
        public init?(tag: String) {
            guard let hash = tag.lastIndex(of: "#") else { return nil }
            let digits = tag[tag.index(after: hash)...]
            guard (1...9).contains(digits.count),
                  digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(digits), number > 0
            else { return nil }
            var prefix = tag[..<hash]
            if prefix.count > 1, prefix.hasSuffix("/") {
                prefix = prefix.dropLast()
            }
            if prefix.isEmpty {
                repository = nil
            } else {
                let parts = prefix.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count <= 2, parts.allSatisfy({ Repository.isName($0) }) else { return nil }
                repository = String(prefix)
            }
            self.number = number
        }
    }

    /// The web address of the issue or pull request `tag` refers to, given a
    /// project's repositories, or nil when the tag isn't a reference or
    /// names a repository the project doesn't have.
    public static func url(forTag tag: String, repositories: [String]) -> URL? {
        target(ofTag: tag, repositories: repositories).flatMap { URL(string: "\($0.repository.address)/issues/\($0.number)") }
    }

    /// The repository and number `tag` refers to, given a project's
    /// repositories, or nil.
    static func target(ofTag tag: String, repositories: [String]) -> (repository: Repository, number: Int)? {
        guard let reference = Reference(tag: tag) else { return nil }
        let known = repositories.compactMap { Repository($0) }
        let repository: Repository?
        if let written = reference.repository {
            let parts = written.split(separator: "/").map(String.init)
            if parts.count == 2 {
                repository = known.first { same($0.owner, parts[0]) && same($0.name, parts[1]) }
                    ?? Repository(host: known.first?.host ?? "github.com", owner: parts[0], name: parts[1])
            } else {
                repository = known.first { same($0.name, written) }
            }
        } else {
            repository = known.first
        }
        return repository.map { (repository: $0, number: reference.number) }
    }

    /// How a tag names `repository` given a project's repositories: by its
    /// name alone, as in "web#123", when it's one of them and the only one
    /// with that name, and otherwise by its owner and name, as in
    /// "acme/web#123", which refers to it whatever the project has.
    static func prefix(for repository: Repository, among repositories: [String]) -> String {
        let known = repositories.compactMap { Repository($0) }
        let listed = known.contains { same($0.address, repository.address) }
        let namesakes = known.filter { same($0.name, repository.name) }.count
        return listed && namesakes == 1 ? repository.name : "\(repository.owner)/\(repository.name)"
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.lowercased() == b.lowercased()
    }
}

extension Ledger {
    /// Sets a project's GitHub repositories.
    ///
    /// What a tag refers to depends on the repositories: "#123" on the
    /// first, "web#123" on there being one named "web". So when a change
    /// would send a tag on the project's entries to another issue, or to
    /// none, the tag is rewritten to name the repository it meant, such as
    /// "web#123", or "acme/web#123" once that's removed, and keeps opening
    /// the same issue. A tag written with a slash before the "#" keeps it,
    /// as in "acme/web/#123". Removing the last repository leaves the tags
    /// as they are, for the next one added.
    @discardableResult
    public mutating func setRepositories(_ repositories: [String], ofProject projectID: UUID, now: Timestamp) -> Changes {
        guard let project = projects[projectID] else { return Changes() }
        let before = project.repositories
        var changes = updateProject(projectID, now: now) { $0.repositories = repositories }
        guard repositories.contains(where: { GitHub.Repository($0) != nil }) else { return changes }
        func kept(_ tag: String) -> String {
            guard let meant = GitHub.target(ofTag: tag, repositories: before) else { return tag }
            let current = GitHub.target(ofTag: tag, repositories: repositories)
            guard current?.repository.address.lowercased() != meant.repository.address.lowercased() else { return tag }
            let hash = tag.contains("/#") ? "/#" : "#"
            return "\(GitHub.prefix(for: meant.repository, among: repositories))\(hash)\(meant.number)"
        }
        for entry in entries.values where entry.projectID == projectID && !entry.isDeleted {
            let tags = entry.tags.map(kept)
            guard tags != entry.tags else { continue }
            changes.formUnion(updateEntry(entry.id, now: now) { $0.tags = tags })
        }
        return changes
    }

    /// The web address of the issue or pull request `tag` refers to, in the
    /// repositories of the entry's project, or nil.
    public func issueURL(forTag tag: String, projectID: UUID?) -> URL? {
        GitHub.url(forTag: tag, repositories: projectID.flatMap { projects[$0]?.repositories } ?? [])
    }

    /// The tags among `tags` that refer to issues or pull requests, with
    /// their web addresses.
    public func issueLinks(tags: [String], projectID: UUID?) -> [String: URL] {
        var links: [String: URL] = [:]
        for tag in tags {
            links[tag] = issueURL(forTag: tag, projectID: projectID)
        }
        return links
    }
}
