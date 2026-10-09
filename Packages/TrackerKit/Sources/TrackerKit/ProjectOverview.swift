import SwiftUI
import TrackerCore

// What a project's page shows, and how the projects list groups them.

/// A project's time and tags, for its page: its time this week, this month
/// and in all, and its tags with their time, the ones that refer to issues
/// grouped by repository. The running timer counts as far as it has run.
public struct ProjectOverview {
    /// A tag with how many of the entries have it, and their time.
    public struct Tag: Identifiable, Hashable {
        /// As most recently spelled.
        public var name: String
        public var count: Int
        public var milliseconds: Int64
        /// The issue or pull request's number, for a tag that refers to one.
        public var number: Int?
        /// Its web address, for a tag that refers to an issue.
        public var url: URL?

        /// The tag lowercased, which tells tags apart.
        public var id: String { name.lowercased() }
    }

    /// The issues of one repository among the tags, and the time of the
    /// entries tagged with any of them.
    public struct Repository: Identifiable, Hashable {
        /// The repository's address, lowercased, which tells them apart.
        public var id: String
        /// Such as "acme/web".
        public var title: String
        public var milliseconds: Int64
        /// The most time first.
        public var issues: [Tag]
    }

    public var thisWeek: Int64
    public var thisMonth: Int64
    public var total: Int64
    public var entryCount: Int
    /// The day of the first entry.
    public var firstDay: LocalDate?
    /// Whether the running timer is one of the entries.
    public var isRunning: Bool
    /// The first of this month's entries that ran long, as corrections
    /// find them: its day, its length, and whether it ran overnight.
    public var longTimer: (day: LocalDate, length: Int64, overnight: Bool)?
    /// The tags that don't refer to issues, the most time first.
    public var tags: [Tag]
    /// The tags that refer to issues, by repository, the most time first.
    public var repositories: [Repository]

    /// The overview of a project's entries as the model has them now.
    @MainActor
    public init(project projectID: UUID, model: AppModel) {
        self.init(project: projectID, ledger: model.ledger, resolved: model.resolved, today: model.today, firstWeekday: model.firstWeekday, now: model.now)
    }

    /// The overview of the entries of `projectID`. Weeks start on
    /// `firstWeekday`.
    init(project projectID: UUID, ledger: Ledger, resolved: [ResolvedEntry], today: LocalDate, firstWeekday: Int, now: Timestamp) {
        let week = ReportPeriod.week.range(containing: today, firstWeekday: firstWeekday)
        let month = ReportPeriod.month.range(containing: today, firstWeekday: firstWeekday)

        var thisWeek: Int64 = 0
        var thisMonth: Int64 = 0
        var total: Int64 = 0
        var entryCount = 0
        var firstDay: LocalDate?
        var isRunning = false
        var longTimer: (day: LocalDate, length: Int64, overnight: Bool)?
        var spelling: [String: String] = [:]
        var tagCount: [String: Int] = [:]
        var tagTime: [String: Int64] = [:]
        var repositoryTime: [String: Int64] = [:]

        // What each tag refers to, worked out once for each.
        var issues: [String: (repository: GitHub.Repository, number: Int, url: URL)] = [:]
        var plain: Set<String> = []
        func issue(_ tag: String, key: String) -> (repository: GitHub.Repository, number: Int, url: URL)? {
            if let known = issues[key] {
                return known
            }
            guard !plain.contains(key), let found = ledger.issue(forTag: tag, projectID: projectID) else {
                plain.insert(key)
                return nil
            }
            issues[key] = found
            return found
        }

        for entry in resolved where entry.entry.projectID == projectID {
            let duration = entry.duration(now: now)
            let day = entry.entry.day
            entryCount += 1
            total += duration
            if week.contains(day) { thisWeek += duration }
            if month.contains(day) {
                thisMonth += duration
                // Entries are in order of start, so the first found is the
                // first that ran long.
                if longTimer == nil, let overnight = Corrections.ranLong(entry, now: now) {
                    longTimer = (day: day, length: duration, overnight: overnight)
                }
            }
            firstDay = min(firstDay ?? day, day)
            isRunning = isRunning || entry.isRunning
            var seen: Set<String> = []
            var entryRepositories: Set<String> = []
            for tag in entry.entry.tags {
                let key = tag.lowercased()
                guard seen.insert(key).inserted else { continue }
                // Entries are in order of start, so the latest spelling wins,
                // as in the tag lists elsewhere.
                spelling[key] = tag
                tagCount[key, default: 0] += 1
                tagTime[key, default: 0] += duration
                if let issue = issue(tag, key: key) {
                    entryRepositories.insert(issue.repository.address.lowercased())
                }
            }
            for repository in entryRepositories {
                repositoryTime[repository, default: 0] += duration
            }
        }

        // Most time first, then in the order tags are listed in.
        func busiestFirst(_ a: Tag, _ b: Tag) -> Bool {
            a.milliseconds != b.milliseconds ? a.milliseconds > b.milliseconds : Tags.order(a.name, b.name)
        }
        let allTags = tagTime.keys.map { key in
            Tag(
                name: spelling[key] ?? key,
                count: tagCount[key, default: 0],
                milliseconds: tagTime[key, default: 0],
                number: issues[key]?.number,
                url: issues[key]?.url
            )
        }
        var byRepository: [String: (repository: GitHub.Repository, issues: [Tag])] = [:]
        for tag in allTags {
            guard let issue = issues[tag.id] else { continue }
            let key = issue.repository.address.lowercased()
            byRepository[key, default: (repository: issue.repository, issues: [])].issues.append(tag)
        }

        tags = allTags.filter { $0.url == nil }.sorted(by: busiestFirst)
        repositories = byRepository
            .map { key, value in
                Repository(id: key, title: value.repository.title, milliseconds: repositoryTime[key, default: 0], issues: value.issues.sorted(by: busiestFirst))
            }
            .sorted { a, b in a.milliseconds != b.milliseconds ? a.milliseconds > b.milliseconds : a.title.lowercased() < b.title.lowercased() }
        self.thisWeek = thisWeek
        self.thisMonth = thisMonth
        self.total = total
        self.entryCount = entryCount
        self.firstDay = firstDay
        self.isRunning = isRunning
        self.longTimer = longTimer
    }

    /// Every tag's name, for telling whether a new name is another tag's.
    public var tagNames: [String] {
        tags.map(\.name) + repositories.flatMap { $0.issues.map(\.name) }
    }
}

/// Clients and their projects, as the projects list groups them: the
/// clients with their projects, then the projects without a client, and
/// apart from them the archived clients and projects, each by name.
public struct ProjectTree {
    /// A client and its projects.
    public struct Branch: Identifiable {
        public var client: Client
        public var projects: [Project]

        public var id: UUID { client.id }
    }

    /// The clients that aren't archived, with their projects that aren't.
    public var clients: [Branch]
    /// The projects without a client that aren't archived.
    public var unfiled: [Project]
    /// The archived clients, with all their projects.
    public var archivedClients: [Branch]
    /// The archived projects of other clients or of none, and the projects
    /// of a deleted client, which show as archived, by title.
    public var archivedProjects: [Project]

    public init(ledger: Ledger) {
        let projects = ledger.projects.values
            .filter { !$0.isDeleted }
            .sorted(by: Project.fileOrder)
        let live = ledger.liveClients()
        clients = live.filter { !$0.archived }.map { client in
            Branch(client: client, projects: projects.filter { $0.clientID == client.id && !$0.archived })
        }
        archivedClients = live.filter(\.archived).map { client in
            Branch(client: client, projects: projects.filter { $0.clientID == client.id })
        }
        unfiled = projects.filter { !$0.archived && ledger.client(forProject: $0.id) == nil }
        archivedProjects = projects
            .filter { project in
                guard let clientID = project.clientID, let client = ledger.clients[clientID] else {
                    return project.archived
                }
                return client.isDeleted || (project.archived && !client.archived)
            }
            .sorted { ledger.projectTitle($0.id).lowercased() < ledger.projectTitle($1.id).lowercased() }
    }

    /// Every project listed as archived: the archived projects, then the
    /// projects of the archived clients.
    public var allArchivedProjects: [Project] {
        archivedProjects + archivedClients.flatMap(\.projects)
    }
}
