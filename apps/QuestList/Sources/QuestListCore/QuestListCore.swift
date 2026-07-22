import Combine
import Foundation

public final class QuestStore: ObservableObject {
    @Published public var goals: [Goal] = []
    @Published public var quests: [Quest] = []
    @Published public var logs: [ProgressLog] = []
    @Published public var occurrenceStates: [QuestOccurrenceState] = []
    @Published public var occurrenceFutureOverrides: [QuestOccurrenceFutureOverride] = []
    @Published public var profile: PlayerProfile = PlayerProfile()

    private let storageURL: URL

    public init(storageURL: URL = QuestStore.defaultStorageURL) {
        self.storageURL = storageURL
        load()
        seedIfEmpty()
    }

    public static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("QuestList", isDirectory: true).appendingPathComponent("questlist.json")
    }

    public func addGoal(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        goals.append(Goal(name: trimmed))
        save()
    }

    public func addQuest(goalID: UUID?) -> UUID {
        let quest = Quest(title: "", goalID: goalID)
        quests.insert(quest, at: 0)
        save()
        return quest.id
    }

    public func updateQuest(id: UUID, mutate: (inout Quest) -> Void) {
        guard let index = quests.firstIndex(where: { $0.id == id }) else { return }
        var updatedQuest = quests[index]
        mutate(&updatedQuest)
        guard updatedQuest != quests[index] else { return }
        quests[index] = updatedQuest
        save()
    }

    public func completeQuest(id: UUID, now: Date = .now) {
        updateQuest(id: id) { quest in
            quest.isCompleted = true
            quest.completedAt = now
            guard !quest.xpAwarded else { return }
            quest.xpAwarded = true
            profile.totalXP += quest.xpReward
        }
        save()
    }

    public func deleteQuest(id: UUID) {
        updateQuest(id: id) { quest in
            quest.deletedAt = .now
        }
    }

    public func restoreQuest(id: UUID) {
        updateQuest(id: id) { quest in
            quest.deletedAt = nil
        }
    }

    public func deletedQuests() -> [Quest] {
        quests.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    public func addLog(questID: UUID, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logs.insert(ProgressLog(content: trimmed, questID: questID), at: 0)
        save()
    }

    public func addOccurrenceLog(parentQuestID: UUID, date: Date, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let occurrenceID = QuestOccurrence(parentQuestID: parentQuestID, date: date).id
        logs.insert(ProgressLog(content: trimmed, questID: parentQuestID, occurrenceID: occurrenceID), at: 0)
        save()
    }

    public func listItems(in timeFilter: QuestTimeFilter, now: Date = .now, calendar: Calendar = .current) -> [QuestListItem] {
        quests.flatMap { quest -> [QuestListItem] in
            guard quest.deletedAt == nil else { return [] }
            if quest.recurrenceRule != nil {
                return quest.generateOccurrences(in: timeFilter, now: now, calendar: calendar).map { occurrence in
                    item(for: occurrence, parent: quest)
                }
            }
            let displayDate = quest.effectiveDisplayDate(now: now, calendar: calendar)
            guard timeFilter.contains(displayDate, now: now, calendar: calendar) else { return [] }
            return [QuestListItem(quest: quest, now: now, calendar: calendar)]
        }
        .sorted { lhs, rhs in
            if lhs.displayDate != rhs.displayDate {
                return lhs.displayDate < rhs.displayDate
            }
            return lhs.title < rhs.title
        }
    }

    public func detailTarget(for selectedItemID: String, in timeFilter: QuestTimeFilter, now: Date = .now, calendar: Calendar = .current, includesDeleted: Bool = false) -> QuestDetailTarget? {
        if let questID = UUID(uuidString: selectedItemID), let matchedQuest = quest(id: questID), includesDeleted || matchedQuest.deletedAt == nil {
            return .quest(questID)
        }
        guard let item = listItems(in: timeFilter, now: now, calendar: calendar).first(where: { $0.id == selectedItemID }) else { return nil }
        if item.isOccurrence {
            return .occurrence(item)
        }
        return .quest(item.questID)
    }

    public func completeOccurrence(parentQuestID: UUID, date: Date) {
        guard let parent = quest(id: parentQuestID) else { return }
        let index = occurrenceStateIndex(parentQuestID: parentQuestID, date: date)
        if let index {
            guard !occurrenceStates[index].xpAwarded else {
                occurrenceStates[index].isCompleted = true
                save()
                return
            }
            occurrenceStates[index].isCompleted = true
            occurrenceStates[index].xpAwarded = true
            occurrenceStates[index].completedAt = .now
        } else {
            occurrenceStates.append(QuestOccurrenceState(parentQuestID: parentQuestID, date: date, isCompleted: true, completedAt: .now, xpAwarded: true))
        }
        let xpReward = occurrenceXPReward(parentQuestID: parentQuestID, date: date, parent: parent)
        profile.totalXP += xpReward
        save()
    }

    public func updateOccurrenceCompletion(parentQuestID: UUID, date: Date, isCompleted: Bool) {
        if isCompleted {
            completeOccurrence(parentQuestID: parentQuestID, date: date)
            return
        }
        if let index = occurrenceStateIndex(parentQuestID: parentQuestID, date: date) {
            occurrenceStates[index].isCompleted = false
            save()
        }
    }

    public func applyOccurrenceOverride(parentQuestID: UUID, date: Date, scope: OccurrenceEditScope, override: QuestOccurrenceOverride) {
        switch scope {
        case .once:
            let index = occurrenceStateIndex(parentQuestID: parentQuestID, date: date)
            if let index {
                occurrenceStates[index].override = override
            } else {
                occurrenceStates.append(QuestOccurrenceState(parentQuestID: parentQuestID, date: date, override: override))
            }
        case .future:
            occurrenceFutureOverrides.removeAll { existing in
                existing.parentQuestID == parentQuestID && Calendar.current.isDate(existing.startDate, inSameDayAs: date)
            }
            occurrenceFutureOverrides.append(QuestOccurrenceFutureOverride(parentQuestID: parentQuestID, startDate: date, override: override))
        }
        save()
    }

    public func occurrenceState(parentQuestID: UUID, date: Date) -> QuestOccurrenceState? {
        guard let index = occurrenceStateIndex(parentQuestID: parentQuestID, date: date) else { return nil }
        return occurrenceStates[index]
    }

    public func quest(id: UUID?) -> Quest? {
        guard let id else { return nil }
        return quests.first { $0.id == id }
    }

    public func goal(id: UUID?) -> Goal? {
        guard let id else { return nil }
        return goals.first { $0.id == id }
    }

    public func logs(for questID: UUID) -> [ProgressLog] {
        logs.filter { $0.questID == questID && $0.occurrenceID == nil }.sorted { $0.timestamp > $1.timestamp }
    }

    public func logs(forOccurrenceID occurrenceID: String) -> [ProgressLog] {
        logs.filter { $0.occurrenceID == occurrenceID }.sorted { $0.timestamp > $1.timestamp }
    }

    public func questTitle(for questID: UUID) -> String {
        quest(id: questID)?.title ?? "未知任务"
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let snapshot = try? JSONDecoder.questList.decode(QuestSnapshot.self, from: data) else { return }
        goals = snapshot.goals
        quests = snapshot.quests
        occurrenceStates = snapshot.occurrenceStates
        occurrenceFutureOverrides = snapshot.occurrenceFutureOverrides
        logs = snapshot.logs.sorted { $0.timestamp > $1.timestamp }
        profile = snapshot.profile
        purgeExpiredDeletions()
    }

    private static let deletionRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

    private func purgeExpiredDeletions(now: Date = .now) {
        let expiredIDs = Set(quests.filter { quest in
            guard let deletedAt = quest.deletedAt else { return false }
            return now.timeIntervalSince(deletedAt) > Self.deletionRetentionInterval
        }.map(\.id))
        guard !expiredIDs.isEmpty else { return }
        quests.removeAll { expiredIDs.contains($0.id) }
        logs.removeAll { expiredIDs.contains($0.questID) }
        save()
    }

    private func save() {
        let snapshot = QuestSnapshot(
            goals: goals,
            quests: quests,
            logs: logs,
            profile: profile,
            occurrenceStates: occurrenceStates,
            occurrenceFutureOverrides: occurrenceFutureOverrides
        )
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.questList.encode(snapshot)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save QuestList data: \(error)")
        }
    }

    private func seedIfEmpty() {
        guard goals.isEmpty && quests.isEmpty else { return }
        let learning = Goal(name: "学习成长", accentName: "blue")
        let wellness = Goal(name: "健康生活", accentName: "green")
        goals = [learning, wellness]
        quests = [
            Quest(
                title: "规划第一块任务看板",
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                category: .main,
                difficulty: .medium,
                reward: "一杯咖啡",
                goalID: learning.id
            ),
            Quest(
                title: "出门散步 20 分钟",
                dueDate: .now,
                category: .daily,
                difficulty: .easy,
                reward: "听一首喜欢的歌",
                goalID: wellness.id
            )
        ]
        save()
    }

    private func item(for occurrence: QuestOccurrence, parent: Quest) -> QuestListItem {
        let state = occurrenceState(parentQuestID: occurrence.parentQuestID, date: occurrence.date)
        let override = mergedOverride(parentQuestID: occurrence.parentQuestID, date: occurrence.date, stateOverride: state?.override)
        return QuestListItem(parent: parent, occurrence: occurrence, state: state, override: override)
    }

    private func occurrenceXPReward(parentQuestID: UUID, date: Date, parent: Quest) -> Int {
        let state = occurrenceState(parentQuestID: parentQuestID, date: date)
        let override = mergedOverride(parentQuestID: parentQuestID, date: date, stateOverride: state?.override)
        return override?.xpReward ?? parent.baseXPReward
    }

    private func occurrenceStateIndex(parentQuestID: UUID, date: Date) -> Int? {
        let occurrenceID = QuestOccurrence(parentQuestID: parentQuestID, date: date).id
        return occurrenceStates.firstIndex { $0.id == occurrenceID }
    }

    private func mergedOverride(parentQuestID: UUID, date: Date, stateOverride: QuestOccurrenceOverride?) -> QuestOccurrenceOverride? {
        let futureOverride = occurrenceFutureOverrides
            .filter { $0.parentQuestID == parentQuestID && $0.startDate <= date }
            .sorted { $0.startDate < $1.startDate }
            .last?
            .override
        return futureOverride?.merging(stateOverride) ?? stateOverride
    }
}

public struct QuestSnapshot: Codable {
    public var goals: [Goal]
    public var quests: [Quest]
    public var logs: [ProgressLog]
    public var profile: PlayerProfile
    public var occurrenceStates: [QuestOccurrenceState]
    public var occurrenceFutureOverrides: [QuestOccurrenceFutureOverride]

    public init(
        goals: [Goal],
        quests: [Quest],
        logs: [ProgressLog],
        profile: PlayerProfile,
        occurrenceStates: [QuestOccurrenceState] = [],
        occurrenceFutureOverrides: [QuestOccurrenceFutureOverride] = []
    ) {
        self.goals = goals
        self.quests = quests
        self.logs = logs
        self.profile = profile
        self.occurrenceStates = occurrenceStates
        self.occurrenceFutureOverrides = occurrenceFutureOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case goals
        case quests
        case logs
        case profile
        case occurrenceStates
        case occurrenceFutureOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goals = try container.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        quests = try container.decodeIfPresent([Quest].self, forKey: .quests) ?? []
        logs = try container.decodeIfPresent([ProgressLog].self, forKey: .logs) ?? []
        profile = try container.decodeIfPresent(PlayerProfile.self, forKey: .profile) ?? PlayerProfile()
        occurrenceStates = try container.decodeIfPresent([QuestOccurrenceState].self, forKey: .occurrenceStates) ?? []
        occurrenceFutureOverrides = try container.decodeIfPresent([QuestOccurrenceFutureOverride].self, forKey: .occurrenceFutureOverrides) ?? []
    }
}

public struct Goal: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var accentName: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, accentName: String = "blue", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.accentName = accentName
        self.createdAt = createdAt
    }
}

public struct Quest: Identifiable, Codable, Hashable {
    public var id: UUID
    public var title: String
    public var dueDate: Date?
    public var category: QuestCategory
    public var difficulty: QuestDifficulty
    public var reward: String
    public var isCompleted: Bool
    public var xpAwarded: Bool
    public var createdAt: Date
    public var startDate: Date
    public var completedAt: Date?
    public var goalID: UUID?
    public var recurrenceRule: QuestRecurrenceRule?
    public var deletedAt: Date?
    public var baseXPReward: Int

    public init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        category: QuestCategory = .side,
        difficulty: QuestDifficulty = .medium,
        reward: String = "",
        isCompleted: Bool = false,
        xpAwarded: Bool = false,
        createdAt: Date = .now,
        startDate: Date? = nil,
        completedAt: Date? = nil,
        goalID: UUID? = nil,
        recurrenceRule: QuestRecurrenceRule? = nil,
        deletedAt: Date? = nil,
        baseXPReward: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.category = category
        self.difficulty = difficulty
        self.reward = reward
        self.isCompleted = isCompleted
        self.xpAwarded = xpAwarded
        self.createdAt = createdAt
        self.startDate = startDate ?? createdAt
        self.completedAt = completedAt
        self.goalID = goalID
        self.recurrenceRule = recurrenceRule
        self.deletedAt = deletedAt
        self.baseXPReward = baseXPReward ?? difficulty.xpReward
    }

    public var xpReward: Int { baseXPReward }

    public var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名任务" : title
    }

    public var displayDate: Date {
        dueDate ?? startDate
    }

    public func effectiveDisplayDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        if let dueDate {
            return dueDate
        }
        if isCompleted {
            return completedAt ?? startDate
        }

        let startDay = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        guard startDay <= today else { return startDate }

        let time = calendar.dateComponents([.hour, .minute, .second], from: startDate)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: today
        ) ?? now
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueDate
        case category
        case difficulty
        case reward
        case isCompleted
        case xpAwarded
        case createdAt
        case startDate
        case completedAt
        case goalID
        case recurrenceRule
        case deletedAt
        case baseXPReward
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        self.category = try container.decodeIfPresent(QuestCategory.self, forKey: .category) ?? .side
        self.difficulty = try container.decodeIfPresent(QuestDifficulty.self, forKey: .difficulty) ?? .medium
        self.reward = try container.decodeIfPresent(String.self, forKey: .reward) ?? ""
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.xpAwarded = try container.decodeIfPresent(Bool.self, forKey: .xpAwarded) ?? false
        self.createdAt = createdAt
        self.startDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? createdAt
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.goalID = try container.decodeIfPresent(UUID.self, forKey: .goalID)
        self.recurrenceRule = try container.decodeIfPresent(QuestRecurrenceRule.self, forKey: .recurrenceRule)
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        let decodedDifficulty = self.difficulty
        self.baseXPReward = try container.decodeIfPresent(Int.self, forKey: .baseXPReward) ?? decodedDifficulty.xpReward
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(category, forKey: .category)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(reward, forKey: .reward)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(xpAwarded, forKey: .xpAwarded)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(goalID, forKey: .goalID)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(baseXPReward, forKey: .baseXPReward)
    }
}

public enum QuestRecurrenceRule: Codable, Hashable {
    case daily
    case weekdays
    case weekly(weekdays: Set<QuestWeekday>)
    case monthly(day: Int)
    case yearly(month: Int, day: Int)
    case fixedInterval(value: Int, unit: RecurrenceIntervalUnit)
}

public enum QuestWeekday: Int, CaseIterable, Codable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
}

public enum RecurrenceIntervalUnit: String, Codable, Hashable {
    case day
    case week
}

public struct QuestOccurrence: Identifiable, Codable, Hashable {
    public var parentQuestID: UUID
    public var date: Date

    public init(parentQuestID: UUID, date: Date) {
        self.parentQuestID = parentQuestID
        self.date = date
    }

    public var id: String {
        "\(parentQuestID.uuidString)-\(Int(date.timeIntervalSince1970))"
    }
}

public struct QuestOccurrenceOverride: Codable, Hashable {
    public var title: String?
    public var reward: String?
    public var category: QuestCategory?
    public var difficulty: QuestDifficulty?
    public var dueDate: Date?
    public var xpReward: Int?

    public init(title: String? = nil, reward: String? = nil, category: QuestCategory? = nil, difficulty: QuestDifficulty? = nil, dueDate: Date? = nil, xpReward: Int? = nil) {
        self.title = title
        self.reward = reward
        self.category = category
        self.difficulty = difficulty
        self.dueDate = dueDate
        self.xpReward = xpReward
    }

    public func merging(_ override: QuestOccurrenceOverride?) -> QuestOccurrenceOverride {
        guard let override else { return self }
        return QuestOccurrenceOverride(
            title: override.title ?? title,
            reward: override.reward ?? reward,
            category: override.category ?? category,
            difficulty: override.difficulty ?? difficulty,
            dueDate: override.dueDate ?? dueDate,
            xpReward: override.xpReward ?? xpReward
        )
    }
}

public enum OccurrenceEditScope: String, CaseIterable, Identifiable, Codable, Hashable {
    case once
    case future

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .once: "仅这一次"
        case .future: "之后全部"
        }
    }
}

public struct QuestOccurrenceState: Identifiable, Codable, Hashable {
    public var parentQuestID: UUID
    public var date: Date
    public var isCompleted: Bool
    public var completedAt: Date?
    public var xpAwarded: Bool
    public var override: QuestOccurrenceOverride?

    public init(
        parentQuestID: UUID,
        date: Date,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        xpAwarded: Bool = false,
        override: QuestOccurrenceOverride? = nil
    ) {
        self.parentQuestID = parentQuestID
        self.date = date
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.xpAwarded = xpAwarded
        self.override = override
    }

    public var id: String {
        QuestOccurrence(parentQuestID: parentQuestID, date: date).id
    }
}

public struct QuestOccurrenceFutureOverride: Identifiable, Codable, Hashable {
    public var parentQuestID: UUID
    public var startDate: Date
    public var override: QuestOccurrenceOverride

    public init(parentQuestID: UUID, startDate: Date, override: QuestOccurrenceOverride) {
        self.parentQuestID = parentQuestID
        self.startDate = startDate
        self.override = override
    }

    public var id: String {
        "\(parentQuestID.uuidString)-future-\(Int(startDate.timeIntervalSince1970))"
    }
}

public enum QuestDetailTarget: Hashable {
    case quest(UUID)
    case occurrence(QuestListItem)
}

public struct QuestListItem: Identifiable, Hashable {
    public var id: String
    public var questID: UUID
    public var occurrenceDate: Date?
    public var title: String
    public var dueDate: Date?
    public var category: QuestCategory
    public var difficulty: QuestDifficulty
    public var reward: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var xpAwarded: Bool
    public var goalID: UUID?
    public var xpReward: Int
    public var displayDate: Date

    public init(quest: Quest, now: Date = .now, calendar: Calendar = .current) {
        self.id = quest.id.uuidString
        self.questID = quest.id
        self.occurrenceDate = nil
        self.title = quest.title
        self.dueDate = quest.dueDate
        self.category = quest.category
        self.difficulty = quest.difficulty
        self.reward = quest.reward
        self.isCompleted = quest.isCompleted
        self.completedAt = quest.completedAt
        self.xpAwarded = quest.xpAwarded
        self.goalID = quest.goalID
        self.xpReward = quest.baseXPReward
        self.displayDate = quest.effectiveDisplayDate(now: now, calendar: calendar)
    }

    public init(parent: Quest, occurrence: QuestOccurrence, state: QuestOccurrenceState?, override: QuestOccurrenceOverride?) {
        self.id = occurrence.id
        self.questID = parent.id
        self.occurrenceDate = occurrence.date
        self.title = override?.title ?? parent.title
        self.dueDate = override?.dueDate ?? occurrence.date
        self.category = override?.category ?? parent.category
        self.difficulty = override?.difficulty ?? parent.difficulty
        self.reward = override?.reward ?? parent.reward
        self.isCompleted = state?.isCompleted ?? false
        self.completedAt = state?.completedAt
        self.xpAwarded = state?.xpAwarded ?? false
        self.goalID = parent.goalID
        self.xpReward = override?.xpReward ?? parent.baseXPReward
        self.displayDate = override?.dueDate ?? occurrence.date
    }

    public var isOccurrence: Bool { occurrenceDate != nil }
}

public extension Quest {
    func generateOccurrences(in timeFilter: QuestTimeFilter, now: Date = .now, calendar: Calendar = .current) -> [QuestOccurrence] {
        guard let recurrenceRule else { return [] }
        if timeFilter == .future {
            return nextFutureOccurrence(recurrenceRule: recurrenceRule, now: now, calendar: calendar)
        }
        let start = calendar.startOfDay(for: max(startDate, timeFilter.dateInterval(now: now, calendar: calendar)?.start ?? startDate))
        let generationEnd = generationEnd(for: timeFilter, now: now, calendar: calendar)
        guard start < generationEnd else { return [] }

        var occurrences: [QuestOccurrence] = []
        var current = start
        while current < generationEnd {
            if matches(current, recurrenceRule: recurrenceRule, calendar: calendar) && timeFilter.contains(current, now: now, calendar: calendar) {
                occurrences.append(QuestOccurrence(parentQuestID: id, date: current))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return occurrences
    }

    private func nextFutureOccurrence(recurrenceRule: QuestRecurrenceRule, now: Date, calendar: Calendar) -> [QuestOccurrence] {
        let futureStart = QuestTimeFilter.future.futureStart(now: now, calendar: calendar)
        let start = calendar.startOfDay(for: max(startDate, futureStart))
        let end: Date
        if let dueDate {
            end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dueDate)) ?? dueDate
        } else {
            let oneYearLater = calendar.date(byAdding: .year, value: 1, to: futureStart) ?? futureStart
            end = calendar.date(byAdding: .day, value: 1, to: oneYearLater) ?? oneYearLater
        }
        guard start < end else { return [] }

        var current = start
        while current < end {
            if matches(current, recurrenceRule: recurrenceRule, calendar: calendar) {
                return [QuestOccurrence(parentQuestID: id, date: current)]
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return []
    }

    private func generationEnd(for timeFilter: QuestTimeFilter, now: Date, calendar: Calendar) -> Date {
        let filterEnd = timeFilter.dateInterval(now: now, calendar: calendar)?.end
            ?? defaultAllGenerationEnd(now: now, calendar: calendar)
        guard let dueDate else { return filterEnd }
        let endOfDueDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dueDate)) ?? dueDate
        return min(filterEnd, endOfDueDate)
    }

    private func defaultAllGenerationEnd(now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .month, value: 1, to: start) ?? now
    }

    private func matches(_ date: Date, recurrenceRule: QuestRecurrenceRule, calendar: Calendar) -> Bool {
        switch recurrenceRule {
        case .daily:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= QuestWeekday.monday.rawValue && weekday <= QuestWeekday.friday.rawValue
        case .weekly(let weekdays):
            guard let weekday = QuestWeekday(rawValue: calendar.component(.weekday, from: date)) else { return false }
            return weekdays.contains(weekday)
        case .monthly(let day):
            return calendar.component(.day, from: date) == day
        case .yearly(let month, let day):
            return calendar.component(.month, from: date) == month && calendar.component(.day, from: date) == day
        case .fixedInterval(let value, let unit):
            guard value > 0 else { return false }
            let start = calendar.startOfDay(for: startDate)
            let current = calendar.startOfDay(for: date)
            guard current >= start else { return false }
            switch unit {
            case .day:
                let days = calendar.dateComponents([.day], from: start, to: current).day ?? 0
                return days % value == 0
            case .week:
                let days = calendar.dateComponents([.day], from: start, to: current).day ?? 0
                return days % (value * 7) == 0
            }
        }
    }
}

public struct QuestItemDateGroup: Identifiable, Hashable {
    public var date: Date
    public var items: [QuestListItem]

    public init(date: Date, items: [QuestListItem]) {
        self.date = date
        self.items = items
    }

    public var id: Date { date }
}

public extension Array where Element == QuestListItem {
    func groupedByDisplayDate(calendar: Calendar = .current) -> [QuestItemDateGroup] {
        let grouped = Dictionary(grouping: self) { item in
            calendar.startOfDay(for: item.displayDate)
        }

        return grouped.keys.sorted().map { date in
            QuestItemDateGroup(
                date: date,
                items: (grouped[date] ?? []).sorted { lhs, rhs in
                    if lhs.displayDate != rhs.displayDate {
                        return lhs.displayDate < rhs.displayDate
                    }
                    return lhs.title < rhs.title
                }
            )
        }
    }
}

public enum QuestTimeFilter: String, CaseIterable, Identifiable, Hashable {
    case today
    case nextThreeDays
    case nextWeek
    case nextMonth
    case future
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "当日"
        case .nextThreeDays: "近三天"
        case .nextWeek: "近一周"
        case .nextMonth: "近一个月"
        case .future: "未来"
        case .all: "所有"
        }
    }

    public func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        if self == .future {
            return date >= futureStart(now: now, calendar: calendar)
        }
        guard let interval = dateInterval(now: now, calendar: calendar) else { return true }
        return date >= interval.start && date < interval.end
    }

    public func dateInterval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let start = calendar.startOfDay(for: now)
        let end: Date?
        switch self {
        case .today:
            end = calendar.date(byAdding: .day, value: 1, to: start)
        case .nextThreeDays:
            end = calendar.date(byAdding: .day, value: 3, to: start)
        case .nextWeek:
            end = calendar.date(byAdding: .day, value: 7, to: start)
        case .nextMonth:
            end = calendar.date(byAdding: .month, value: 1, to: start)
        case .future, .all:
            end = nil
        }

        guard let end else { return nil }
        return DateInterval(start: start, end: end)
    }

    public func futureStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        let todayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
    }
}

public struct QuestDateGroup: Identifiable, Hashable {
    public var date: Date
    public var quests: [Quest]

    public init(date: Date, quests: [Quest]) {
        self.date = date
        self.quests = quests
    }

    public var id: Date { date }
}

public extension Array where Element == Quest {
    func visible(in timeFilter: QuestTimeFilter, now: Date = .now, calendar: Calendar = .current) -> [Quest] {
        filter { quest in
            timeFilter.contains(quest.effectiveDisplayDate(now: now, calendar: calendar), now: now, calendar: calendar)
        }
    }

    func groupedByDisplayDate(timeFilter: QuestTimeFilter, now: Date = .now, calendar: Calendar = .current) -> [QuestDateGroup] {
        let visibleQuests = visible(in: timeFilter, now: now, calendar: calendar)
        let grouped = Dictionary(grouping: visibleQuests) { quest in
            calendar.startOfDay(for: quest.effectiveDisplayDate(now: now, calendar: calendar))
        }

        return grouped.keys.sorted().map { date in
            QuestDateGroup(
                date: date,
                quests: (grouped[date] ?? []).sorted { lhs, rhs in
                    let lhsDisplayDate = lhs.effectiveDisplayDate(now: now, calendar: calendar)
                    let rhsDisplayDate = rhs.effectiveDisplayDate(now: now, calendar: calendar)
                    if lhsDisplayDate != rhsDisplayDate {
                        return lhsDisplayDate < rhsDisplayDate
                    }
                    return lhs.createdAt < rhs.createdAt
                }
            )
        }
    }
}

public struct ProgressLog: Identifiable, Codable, Hashable {
    public var id: UUID
    public var content: String
    public var timestamp: Date
    public var questID: UUID
    public var occurrenceID: String?

    public init(id: UUID = UUID(), content: String, timestamp: Date = .now, questID: UUID, occurrenceID: String? = nil) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.questID = questID
        self.occurrenceID = occurrenceID
    }
}

public struct PlayerProfile: Codable, Hashable {
    public var totalXP: Int

    public init(totalXP: Int = 0) {
        self.totalXP = totalXP
    }

    public var level: Int {
        max(1, totalXP / 100 + 1)
    }

    public var progressToNextLevel: Double {
        Double(totalXP % 100) / 100.0
    }
}

public enum QuestCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case main = "主线任务"
    case side = "支线任务"
    case daily = "每日任务"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .main: "flag.checkered"
        case .side: "sparkles"
        case .daily: "sun.max"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "主线任务", "长期任务", "longTerm":
            self = .main
        case "每日任务", "daily":
            self = .daily
        case "支线任务", "短期任务", "shortTerm":
            self = .side
        default:
            self = .side
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum QuestDifficulty: String, CaseIterable, Identifiable, Codable, Hashable {
    case easy = "简单"
    case medium = "普通"
    case hard = "困难"
    case epic = "史诗"

    public var id: String { rawValue }

    public var xpReward: Int {
        switch self {
        case .easy: 10
        case .medium: 25
        case .hard: 50
        case .epic: 100
        }
    }
}

public extension JSONEncoder {
    static var questList: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var questList: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
