import SwiftUI
import TrackerCore

// What the pages of projects and clients show, and how the sidebars list
// clients and projects, on the Mac and the iPad.

/// A project's time and tags, for its page: its time this week, this month
/// and in all, its last twelve weeks, and its tags with their time, the
/// ones that refer to issues grouped by repository. The running timer
/// counts as far as it has run.
///
/// A client's page sums up its projects, with each project's time and the
/// weeks stacked by project, and lists no tags, since each project has its
/// own. Nil stands for the entries without a project.
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
    /// The last twelve weeks, this week last, stacked by project.
    public var weeks: [ChartColumn]
    /// Each project's time in all, nil's for the unassigned entries.
    public var projects: [UUID?: Int64]
    /// The tags that don't refer to issues, the most time first. Only for
    /// a single project, or the unassigned entries.
    public var tags: [Tag]
    /// The time of the entries without tags.
    public var untagged: Int64
    /// The tags that refer to issues, by repository, the most time first.
    public var repositories: [Repository]

    /// The overview of the entries of `projects`, nil standing for the
    /// unassigned ones. Weeks start on `firstWeekday`.
    public init(projects ids: Set<UUID?>, ledger: Ledger, resolved: [ResolvedEntry], today: LocalDate, firstWeekday: Int, now: Timestamp) {
        let week = ReportPeriod.week.range(containing: today, firstWeekday: firstWeekday)
        let month = ReportPeriod.month.range(containing: today, firstWeekday: firstWeekday)
        let firstWeek = week.lowerBound.adding(days: -7 * 11)
        let listsTags = ids.count == 1
        let projectID = ids.first ?? nil

        var thisWeek: Int64 = 0
        var thisMonth: Int64 = 0
        var total: Int64 = 0
        var entryCount = 0
        var firstDay: LocalDate?
        var isRunning = false
        var byWeek = Array(repeating: [UUID?: Int64](), count: 12)
        var byProject: [UUID?: Int64] = [:]
        var spelling: [String: String] = [:]
        var tagCount: [String: Int] = [:]
        var tagTime: [String: Int64] = [:]
        var untagged: Int64 = 0
        var repositoryTime: [String: Int64] = [:]

        // What each tag refers to, worked out once for each.
        var issues: [String: (repository: GitHub.Repository, number: Int, url: URL)] = [:]
        var plain: Set<String> = []
        func issue(_ tag: String, key: String) -> (repository: GitHub.Repository, number: Int, url: URL)? {
            if let known = issues[key] {
                return known
            }
            guard !plain.contains(key),
                  let url = ledger.issueURL(forTag: tag, projectID: projectID),
                  let number = GitHub.Reference(tag: tag)?.number,
                  // The issue's address is its repository's, then "/issues/123".
                  let repository = GitHub.Repository(url.deletingLastPathComponent().deletingLastPathComponent().absoluteString)
            else {
                plain.insert(key)
                return nil
            }
            let found = (repository: repository, number: number, url: url)
            issues[key] = found
            return found
        }

        for entry in resolved where ids.contains(entry.entry.projectID) {
            let duration = entry.duration(now: now)
            let day = entry.entry.day
            entryCount += 1
            total += duration
            if week.contains(day) { thisWeek += duration }
            if month.contains(day) { thisMonth += duration }
            firstDay = min(firstDay ?? day, day)
            isRunning = isRunning || entry.isRunning
            byProject[entry.entry.projectID, default: 0] += duration
            let sinceFirstWeek = day.daysSince1970 - firstWeek.daysSince1970
            if (0..<84).contains(sinceFirstWeek) {
                byWeek[sinceFirstWeek / 7][entry.entry.projectID, default: 0] += duration
            }

            guard listsTags else { continue }
            if entry.entry.tags.isEmpty {
                untagged += duration
            }
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

        let order = byProject.keys.sorted { a, b in
            let (timeA, timeB) = (byProject[a, default: 0], byProject[b, default: 0])
            return timeA != timeB ? timeA > timeB : ledger.projectTitle(a) < ledger.projectTitle(b)
        }
        weeks = (0..<12).map { index in
            let start = firstWeek.adding(days: 7 * index)
            return ChartColumn(
                id: start.description,
                label: Format.monthDay(start),
                title: Format.days(start...start.adding(days: 6)),
                parts: order.compactMap { projectID in
                    guard let milliseconds = byWeek[index][projectID], milliseconds > 0 else { return nil }
                    return ChartColumn.Part(
                        id: projectID?.uuidString ?? "",
                        title: ledger.projectTitle(projectID),
                        color: ledger.color(ofProject: projectID),
                        milliseconds: milliseconds
                    )
                },
                isCurrent: index == 11
            )
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
        self.projects = byProject
        self.untagged = untagged
    }

    /// One of the tags, plain or referring to an issue, by its id.
    public func tag(_ id: String) -> Tag? {
        tags.first { $0.id == id } ?? repositories.lazy.compactMap { $0.issues.first { $0.id == id } }.first
    }

    /// Every tag's name, for telling whether a new name is another tag's.
    public var tagNames: [String] {
        tags.map(\.name) + repositories.flatMap { $0.issues.map(\.name) }
    }
}

/// Clients and their projects, as the sidebars list them: the clients with
/// their projects, then the projects without a client, and apart from them
/// the archived clients and projects, each by name.
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
            .sorted { a, b in
                let (nameA, nameB) = (a.name.lowercased(), b.name.lowercased())
                return nameA != nameB ? nameA < nameB : a.id.uuidString < b.id.uuidString
            }
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

    /// Whether there are no clients or projects at all.
    public var isEmpty: Bool {
        clients.isEmpty && unfiled.isEmpty && archivedClients.isEmpty && archivedProjects.isEmpty
    }
}
