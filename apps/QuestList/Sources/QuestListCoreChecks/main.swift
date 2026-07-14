import Foundation
import QuestListCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Check failed: \(message)\n", stderr)
        exit(1)
    }
}

func datesAreApproximatelyEqual(_ lhs: Date?, _ rhs: Date?, tolerance: TimeInterval = 1) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    return abs(lhs.timeIntervalSince(rhs)) <= tolerance
}

func day(_ day: Int, calendar: Calendar) -> Date {
    DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: day, hour: 9).date!
}

func md(_ month: Int, _ day: Int, calendar: Calendar) -> Date {
    DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: month, day: day, hour: 9).date!
}

func occurrenceDays(_ occurrences: [QuestOccurrence], calendar: Calendar) -> [Int] {
    occurrences.map { calendar.component(.day, from: $0.date) }
}

func occurrenceMonthDays(_ occurrences: [QuestOccurrence], calendar: Calendar) -> [String] {
    occurrences.map { "\(calendar.component(.month, from: $0.date))-\(calendar.component(.day, from: $0.date))" }
}

func runChecks() throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let newQuest = Quest(title: "测试任务", createdAt: createdAt)
    require(newQuest.startDate == createdAt, "新任务 startDate 应默认等于 createdAt")

    let oldLongTermData = Data("""
    {
      "category" : "长期任务",
      "createdAt" : "2024-01-02T03:04:05Z",
      "difficulty" : "普通",
      "id" : "00000000-0000-0000-0000-000000000001",
      "isCompleted" : false,
      "reward" : "咖啡",
      "title" : "旧任务",
      "xpAwarded" : false
    }
    """.utf8)
    let oldLongTermQuest = try JSONDecoder.questList.decode(Quest.self, from: oldLongTermData)
    require(oldLongTermQuest.startDate == oldLongTermQuest.createdAt, "旧 JSON 缺少 startDate 时应回退到 createdAt")
    require(oldLongTermQuest.category == .main, "旧长期任务应映射为主线任务")

    let oldShortTermData = Data("""
    {
      "category" : "短期任务",
      "createdAt" : "2024-01-02T03:04:05Z",
      "difficulty" : "简单",
      "id" : "00000000-0000-0000-0000-000000000002",
      "isCompleted" : false,
      "title" : "旧短期任务",
      "xpAwarded" : false
    }
    """.utf8)
    let oldShortTermQuest = try JSONDecoder.questList.decode(Quest.self, from: oldShortTermData)
    require(oldShortTermQuest.category == .side, "旧短期任务应映射为支线任务")

    let storageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("questlist.json")
    let store = QuestStore(storageURL: storageURL)
    let questID = store.addQuest(goalID: nil)
    store.completeQuest(id: questID)
    let completedQuest = store.quest(id: questID)
    require(completedQuest?.isCompleted == true, "完成后任务应标记为已完成")
    require(completedQuest?.completedAt != nil, "完成后应记录 completedAt")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let anchor = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 10, hour: 12).date!
    let jan10 = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 10, hour: 9).date!
    let jan11 = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 11, hour: 9).date!
    let jan12 = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 12, hour: 9).date!
    let jan13 = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 13, hour: 9).date!
    let jan10OccurrenceDate = calendar.startOfDay(for: jan10)
    let jan11OccurrenceDate = calendar.startOfDay(for: jan11)

    let quests = [
        Quest(title: "按开始时间显示", category: .main, startDate: jan10),
        Quest(title: "按截止时间显示", dueDate: jan11, category: .main, startDate: jan13),
        Quest(title: "三天内支线", category: .side, startDate: jan12),
        Quest(title: "三天外任务", category: .daily, startDate: jan13)
    ]

    require(QuestTimeFilter.today.title == "当日", "时间筛选器应提供中文标题")
    let visibleTitles = quests.visible(in: .nextThreeDays, now: anchor, calendar: calendar).map(\.title)
    require(visibleTitles == ["按开始时间显示", "按截止时间显示", "三天内支线"], "近三天应包含 1/10、1/11、1/12，排除 1/13")
    require(quests[1].displayDate == jan11, "有截止时间的任务应按截止时间归组")
    require(quests[0].displayDate == jan10, "无截止时间的任务应按开始时间归组")

    let groups = quests.groupedByDisplayDate(timeFilter: .nextThreeDays, now: anchor, calendar: calendar)
    require(groups.map { calendar.component(.day, from: $0.date) } == [10, 11, 12], "任务应按显示日期升序分组")
    require(groups.map { $0.quests.map(\.title) } == [["按开始时间显示"], ["按截止时间显示"], ["三天内支线"]], "每个日期分组应包含对应任务")
    require(QuestTimeFilter.future.title == "未来", "时间筛选器应提供未来标题")
    let futureVisibleTitles = quests.visible(in: .future, now: anchor, calendar: calendar).map(\.title)
    require(futureVisibleTitles == ["按截止时间显示", "三天内支线", "三天外任务"], "未来应排除今天任务，包含明天及之后的任务")

    let dailyParent = Quest(title: "每日任务", startDate: jan10, recurrenceRule: .daily)
    let dailyOccurrences = dailyParent.generateOccurrences(in: .nextThreeDays, now: anchor, calendar: calendar)
    require(occurrenceDays(dailyOccurrences, calendar: calendar) == [10, 11, 12], "每日规则近三天应生成三条 occurrence")
    require(dailyOccurrences.allSatisfy { $0.parentQuestID == dailyParent.id }, "occurrence 应保留父任务 ID")
    let futureDailyOccurrences = dailyParent.generateOccurrences(in: .future, now: anchor, calendar: calendar)
    require(occurrenceDays(futureDailyOccurrences, calendar: calendar) == [11], "每日规则未来筛选应只生成下一次未来 occurrence")

    let weekdayAnchor = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 5, hour: 12).date!
    let weekdayParent = Quest(title: "工作日任务", startDate: day(5, calendar: calendar), recurrenceRule: .weekdays)
    let weekdayOccurrences = weekdayParent.generateOccurrences(in: .nextWeek, now: weekdayAnchor, calendar: calendar)
    require(occurrenceDays(weekdayOccurrences, calendar: calendar) == [5, 8, 9, 10, 11], "工作日规则应跳过周六和周日")

    let weeklyParent = Quest(title: "每周多日任务", startDate: jan10, recurrenceRule: .weekly(weekdays: [.monday, .wednesday]))
    let weeklyOccurrences = weeklyParent.generateOccurrences(in: .nextWeek, now: anchor, calendar: calendar)
    require(occurrenceDays(weeklyOccurrences, calendar: calendar) == [10, 15], "每周自定义多日应只生成选中的星期")
    let futureWeeklyOccurrences = weeklyParent.generateOccurrences(in: .future, now: anchor, calendar: calendar)
    require(occurrenceDays(futureWeeklyOccurrences, calendar: calendar) == [15], "每周规则未来筛选应只生成下一次命中的 occurrence")

    let monthlyParent = Quest(title: "每月任务", startDate: jan10, recurrenceRule: .monthly(day: 15))
    let monthlyOccurrences = monthlyParent.generateOccurrences(in: .nextMonth, now: anchor, calendar: calendar)
    require(occurrenceDays(monthlyOccurrences, calendar: calendar) == [15], "每月几号规则应命中指定日期")

    let yearlyAnchor = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 12, day: 30, hour: 12).date!
    let yearlyParent = Quest(title: "每年任务", startDate: yearlyAnchor, recurrenceRule: .yearly(month: 1, day: 1))
    let yearlyOccurrences = yearlyParent.generateOccurrences(in: .nextMonth, now: yearlyAnchor, calendar: calendar)
    require(occurrenceMonthDays(yearlyOccurrences, calendar: calendar) == ["1-1"], "每年哪天规则应命中指定月日")
    let futureYearlyAnchor = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 2, hour: 12).date!
    let futureYearlyParent = Quest(title: "未来年度任务", startDate: day(2, calendar: calendar), recurrenceRule: .yearly(month: 12, day: 31))
    let futureYearlyOccurrences = futureYearlyParent.generateOccurrences(in: .future, now: futureYearlyAnchor, calendar: calendar)
    require(occurrenceMonthDays(futureYearlyOccurrences, calendar: calendar) == ["12-31"], "年度规则未来筛选应能找到一年内下一次命中")

    let intervalParent = Quest(title: "固定间隔任务", startDate: day(10, calendar: calendar), recurrenceRule: .fixedInterval(value: 2, unit: .day))
    let intervalOccurrences = intervalParent.generateOccurrences(in: .nextWeek, now: anchor, calendar: calendar)
    require(occurrenceDays(intervalOccurrences, calendar: calendar) == [10, 12, 14, 16], "固定间隔规则应按起始时间和间隔生成 occurrence")

    let recurringQuestID = store.addQuest(goalID: nil)
    store.updateQuest(id: recurringQuestID) { quest in
        quest.title = "晨间复盘"
        quest.startDate = jan10
        quest.category = .daily
        quest.difficulty = .easy
        quest.baseXPReward = 10
        quest.reward = "热茶"
        quest.recurrenceRule = .daily
    }

    let projectedItems = store.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
    let recurringItems = projectedItems.filter { $0.questID == recurringQuestID && $0.isOccurrence }
    require(recurringItems.map { calendar.component(.day, from: $0.displayDate) } == [10, 11, 12], "全部任务投影应包含筛选范围内的重复 occurrence")
    require(recurringItems.allSatisfy { $0.category == .daily && $0.reward == "热茶" }, "重复 occurrence 应继承父任务默认配置")
    let futureProjectedItems = store.listItems(in: .future, now: anchor, calendar: calendar)
    let futureRecurringItems = futureProjectedItems.filter { $0.questID == recurringQuestID && $0.isOccurrence }
    require(futureRecurringItems.map { calendar.component(.day, from: $0.displayDate) } == [11], "Store 未来筛选下每个重复父任务只应投影下一次 occurrence")
    require(store.detailTarget(for: recurringQuestID.uuidString, in: .nextThreeDays, now: anchor, calendar: calendar) == .quest(recurringQuestID), "开启重复任务后仍应能通过父任务 ID 打开父任务详情")
    if case .occurrence(let selectedOccurrence)? = store.detailTarget(for: recurringItems[0].id, in: .nextThreeDays, now: anchor, calendar: calendar) {
        require(selectedOccurrence.id == recurringItems[0].id, "点击 occurrence 时应打开 occurrence 详情")
    } else {
        require(false, "点击 occurrence 时应解析为 occurrence 详情")
    }

    store.updateQuest(id: recurringQuestID) { quest in
        quest.category = .main
    }
    require(store.quest(id: recurringQuestID)?.category == .main, "重复规则不应阻止父任务分类切换")
    require(store.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).filter { $0.questID == recurringQuestID && $0.isOccurrence }.allSatisfy { $0.category == .main }, "父任务分类切换后 occurrence 应继承新的任务分区")
    store.updateQuest(id: recurringQuestID) { quest in
        quest.category = .daily
    }

    store.completeOccurrence(parentQuestID: recurringQuestID, date: jan10OccurrenceDate)
    let completedFirstOccurrence = store.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).first { $0.questID == recurringQuestID && calendar.isDate($0.displayDate, inSameDayAs: jan10) }
    let nextOccurrence = store.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).first { $0.questID == recurringQuestID && calendar.isDate($0.displayDate, inSameDayAs: jan11) }
    require(completedFirstOccurrence?.isCompleted == true, "完成一个 occurrence 后当前日期应标记完成")
    require(completedFirstOccurrence?.completedAt != nil, "完成 occurrence 应记录完成时间")
    require(nextOccurrence?.isCompleted == false, "完成一个 occurrence 不应影响其他日期")
    require(store.profile.totalXP == 35, "普通任务和 occurrence 应分别发放 XP，且同一 occurrence 只发放一次")
    store.completeOccurrence(parentQuestID: recurringQuestID, date: jan10OccurrenceDate)
    require(store.profile.totalXP == 35, "同一 occurrence 不能重复领取 XP")

    store.addOccurrenceLog(parentQuestID: recurringQuestID, date: jan10OccurrenceDate, content: "完成 10 分钟")
    require(store.logs(forOccurrenceID: QuestOccurrence(parentQuestID: recurringQuestID, date: jan10OccurrenceDate).id).map(\.content) == ["完成 10 分钟"], "过程记录应只属于当前 occurrence")
    require(store.logs(forOccurrenceID: QuestOccurrence(parentQuestID: recurringQuestID, date: jan11OccurrenceDate).id).isEmpty, "其他日期 occurrence 不应看到当前 occurrence 的过程记录")

    store.applyOccurrenceOverride(
        parentQuestID: recurringQuestID,
        date: jan10OccurrenceDate,
        scope: .once,
        override: QuestOccurrenceOverride(title: "仅今天复盘", reward: "蛋糕", category: .main, difficulty: .hard, dueDate: jan10)
    )
    store.applyOccurrenceOverride(
        parentQuestID: recurringQuestID,
        date: jan11OccurrenceDate,
        scope: .future,
        override: QuestOccurrenceOverride(title: "未来复盘", reward: "咖啡", category: .side, difficulty: .medium, dueDate: jan11)
    )

    let overriddenItems = store.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).filter { $0.questID == recurringQuestID && $0.isOccurrence }
    require(overriddenItems.map(\.title) == ["仅今天复盘", "未来复盘", "未来复盘"], "仅这一次和之后全部 override 应按日期范围生效")
    require(overriddenItems.map(\.category) == [.main, .side, .side], "override 配置应优先于父任务默认配置，且之后全部不影响历史 occurrence")
    require(store.quest(id: recurringQuestID)?.category == .daily, "occurrence 分类 override（仅这一次/之后全部）不应修改父任务默认分类")

    store.applyOccurrenceOverride(
        parentQuestID: recurringQuestID,
        date: jan10OccurrenceDate,
        scope: .once,
        override: QuestOccurrenceOverride(title: "仅今天复盘", reward: "蛋糕", category: .side, difficulty: .hard, dueDate: jan10)
    )
    let onceOverriddenAgain = store.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).first { $0.questID == recurringQuestID && calendar.isDate($0.displayDate, inSameDayAs: jan10) }
    require(onceOverriddenAgain?.category == .side, "仅这一次 override 可再次修改该 occurrence 的分类")
    require(onceOverriddenAgain?.title == "仅今天复盘", "仅这一次 override 重新提交完整表单时应保留其他字段")
    let jan11AfterOnceOverride = store.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).first { $0.questID == recurringQuestID && calendar.isDate($0.displayDate, inSameDayAs: jan11) }
    require(jan11AfterOnceOverride?.category == .side, "仅这一次 override 不应影响其他日期 occurrence 的分类")
    require(store.quest(id: recurringQuestID)?.category == .daily, "再次应用仅这一次 override 仍不应修改父任务默认分类")

    let restoredStore = QuestStore(storageURL: storageURL)
    let restoredItems = restoredStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).filter { $0.questID == recurringQuestID && $0.isOccurrence }
    require(restoredItems.map(\.title) == ["仅今天复盘", "未来复盘", "未来复盘"], "重启后 occurrence override 应恢复")
    require(restoredItems.first?.isCompleted == true, "重启后 occurrence 完成状态应恢复")
    require(restoredStore.logs(forOccurrenceID: QuestOccurrence(parentQuestID: recurringQuestID, date: jan10OccurrenceDate).id).map(\.content) == ["完成 10 分钟"], "重启后 occurrence 过程记录应恢复")
    require(restoredStore.profile.totalXP == 35, "重启后 occurrence XP 发放状态应恢复")

    // --- 空标题与任务级 XP ---
    let xpStorageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("questlist.json")
    let xpStore = QuestStore(storageURL: xpStorageURL)

    let emptyTitleID = xpStore.addQuest(goalID: nil)
    require(xpStore.quest(id: emptyTitleID)?.title == "", "新建任务标题应默认为空字符串")

    let emptyQuest = Quest(title: "")
    require(emptyQuest.displayTitle == "未命名任务", "空标题应展示 fallback '未命名任务'")
    let namedQuest = Quest(title: "读书")
    require(namedQuest.displayTitle == "读书", "非空标题应原样展示")

    let xpQuestID = xpStore.addQuest(goalID: nil)
    require(xpStore.quest(id: xpQuestID)?.baseXPReward == 25, "新建任务 baseXPReward 应使用默认难度普通=25")

    xpStore.updateQuest(id: xpQuestID) { quest in
        quest.baseXPReward = 80
    }
    require(xpStore.quest(id: xpQuestID)?.baseXPReward == 80, "baseXPReward 应支持自定义")

    let xpBeforeCustom = xpStore.profile.totalXP
    xpStore.completeQuest(id: xpQuestID)
    require(xpStore.profile.totalXP == xpBeforeCustom + 80, "完成任务应按 baseXPReward 发放 XP，而不是 difficulty.xpReward")

    let oldXPData = Data("""
    {
      "id": "AAAAAAAA-0000-0000-0000-000000000001",
      "title": "旧任务",
      "difficulty": "困难",
      "category": "主线任务",
      "isCompleted": false,
      "xpAwarded": false,
      "createdAt": "2024-01-10T09:00:00Z"
    }
    """.utf8)
    let decodedOldQuest = try JSONDecoder.questList.decode(Quest.self, from: oldXPData)
    require(decodedOldQuest.baseXPReward == 50, "旧 JSON 缺少 baseXPReward 时应回退为 difficulty.xpReward（困难=50）")

    let xpRecurringID = xpStore.addQuest(goalID: nil)
    xpStore.updateQuest(id: xpRecurringID) { quest in
        quest.title = "XP重复任务"
        quest.startDate = jan10
        quest.recurrenceRule = .daily
        quest.baseXPReward = 60
    }
    let xpOccurrenceItems = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
        .filter { $0.questID == xpRecurringID && $0.isOccurrence }
    require(xpOccurrenceItems.allSatisfy { $0.xpReward == 60 }, "occurrence 默认应继承父任务 baseXPReward")

    xpStore.applyOccurrenceOverride(
        parentQuestID: xpRecurringID,
        date: jan10OccurrenceDate,
        scope: .once,
        override: QuestOccurrenceOverride(xpReward: 99)
    )
    let xpJan10Item = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
        .first { $0.questID == xpRecurringID && calendar.isDate($0.displayDate, inSameDayAs: jan10) }
    require(xpJan10Item?.xpReward == 99, "仅这一次 XP override 应生效")
    let xpJan11Item = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
        .first { $0.questID == xpRecurringID && calendar.isDate($0.displayDate, inSameDayAs: jan11) }
    require(xpJan11Item?.xpReward == 60, "仅这一次 XP override 不影响其他 occurrence")

    xpStore.applyOccurrenceOverride(
        parentQuestID: xpRecurringID,
        date: jan11OccurrenceDate,
        scope: .future,
        override: QuestOccurrenceOverride(xpReward: 77)
    )
    let xpJan11ItemAfterFuture = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
        .first { $0.questID == xpRecurringID && calendar.isDate($0.displayDate, inSameDayAs: jan11) }
    require(xpJan11ItemAfterFuture?.xpReward == 77, "之后全部 XP override 应生效")
    let xpJan10ItemAfterFuture = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
        .first { $0.questID == xpRecurringID && calendar.isDate($0.displayDate, inSameDayAs: jan10) }
    require(xpJan10ItemAfterFuture?.xpReward == 99, "之后全部 XP override 不影响有独立 once override 的 occurrence")
    require(xpStore.quest(id: xpRecurringID)?.baseXPReward == 60, "occurrence XP override 不应修改父任务 baseXPReward")

    let xpBeforeOccurrence = xpStore.profile.totalXP
    xpStore.completeOccurrence(parentQuestID: xpRecurringID, date: jan10OccurrenceDate)
    require(xpStore.profile.totalXP == xpBeforeOccurrence + 99, "完成 occurrence 应按当前投影 XP 发放（含 once override）")

    // --- 已删除任务：数据模型与惰性清理 ---
    let deletionStorageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("questlist.json")
    let deletionStore = QuestStore(storageURL: deletionStorageURL)

    let plainQuestID = deletionStore.addQuest(goalID: nil)
    deletionStore.updateQuest(id: plainQuestID) { quest in
        quest.title = "待删除任务"
        quest.category = .main
        quest.startDate = jan10
    }
    require(deletionStore.quest(id: plainQuestID)?.deletedAt == nil, "新建任务默认不处于已删除状态")
    require(deletionStore.listItems(in: .all, now: anchor, calendar: calendar).contains { $0.questID == plainQuestID }, "删除前任务应出现在全部任务列表中")

    deletionStore.deleteQuest(id: plainQuestID)
    require(deletionStore.quest(id: plainQuestID)?.deletedAt != nil, "删除任务后应记录 deletedAt")
    require(!deletionStore.listItems(in: .all, now: anchor, calendar: calendar).contains { $0.questID == plainQuestID }, "已删除任务不应出现在全部任务列表中")
    require(deletionStore.quest(id: plainQuestID)?.category == .main, "删除任务不应修改原有分类")

    deletionStore.restoreQuest(id: plainQuestID)
    require(deletionStore.quest(id: plainQuestID)?.deletedAt == nil, "恢复任务后应清除删除标记")
    require(deletionStore.listItems(in: .all, now: anchor, calendar: calendar).contains { $0.questID == plainQuestID }, "恢复后任务应重新出现在全部任务列表中")
    require(deletionStore.quest(id: plainQuestID)?.category == .main, "恢复任务后应保留原有分类")

    let completedQuestID = deletionStore.addQuest(goalID: nil)
    deletionStore.updateQuest(id: completedQuestID) { quest in
        quest.startDate = jan10
    }
    deletionStore.completeQuest(id: completedQuestID)
    deletionStore.addLog(questID: completedQuestID, content: "完成心得")
    let xpBeforeDelete = deletionStore.profile.totalXP
    deletionStore.deleteQuest(id: completedQuestID)
    require(deletionStore.profile.totalXP == xpBeforeDelete, "删除已完成任务不应扣回已发放的 XP")
    require(deletionStore.logs(for: completedQuestID).map(\.content) == ["完成心得"], "删除任务后过程记录应保留")
    deletionStore.restoreQuest(id: completedQuestID)
    require(deletionStore.quest(id: completedQuestID)?.isCompleted == true, "恢复任务后完成状态应保持不变")
    require(deletionStore.profile.totalXP == xpBeforeDelete, "恢复任务不应重复发放 XP")

    let deletableRecurringID = deletionStore.addQuest(goalID: nil)
    deletionStore.updateQuest(id: deletableRecurringID) { quest in
        quest.title = "可删除的重复任务"
        quest.startDate = jan10
        quest.recurrenceRule = .daily
    }
    require(deletionStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).contains { $0.questID == deletableRecurringID }, "删除前重复任务的 occurrence 应出现在列表中")
    deletionStore.deleteQuest(id: deletableRecurringID)
    require(!deletionStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).contains { $0.questID == deletableRecurringID }, "删除重复任务父任务后其全部 occurrence 应从列表中隐藏")
    deletionStore.restoreQuest(id: deletableRecurringID)
    require(deletionStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).filter { $0.questID == deletableRecurringID }.count == 3, "恢复重复任务父任务后其 occurrence 应按原规则重新出现")

    require(oldLongTermQuest.deletedAt == nil, "旧 JSON 缺少 deletedAt 字段时应默认视为未删除")

    let purgeStorageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("questlist.json")
    let purgeSeedStore = QuestStore(storageURL: purgeStorageURL)
    let expiredQuestID = purgeSeedStore.addQuest(goalID: nil)
    purgeSeedStore.addLog(questID: expiredQuestID, content: "过期任务的记录")
    purgeSeedStore.updateQuest(id: expiredQuestID) { quest in
        quest.deletedAt = Date().addingTimeInterval(-31 * 24 * 60 * 60)
    }
    let xpBeforePurge = purgeSeedStore.profile.totalXP
    let recentQuestID = purgeSeedStore.addQuest(goalID: nil)
    purgeSeedStore.updateQuest(id: recentQuestID) { quest in
        quest.deletedAt = Date().addingTimeInterval(-1 * 24 * 60 * 60)
    }

    let purgedStore = QuestStore(storageURL: purgeStorageURL)
    require(purgedStore.quest(id: expiredQuestID) == nil, "超过 30 天的已删除任务应在下次启动时被永久清除")
    require(!purgedStore.logs.contains { $0.questID == expiredQuestID }, "被永久清除的任务其过程记录也应一并移除")
    require(purgedStore.profile.totalXP == xpBeforePurge, "永久清除已删除任务不应影响已发放的 XP")
    require(purgedStore.quest(id: recentQuestID)?.deletedAt != nil, "未超过 30 天的已删除任务重启后应仍保留在已删除状态")
    require(purgedStore.deletedQuests().contains { $0.id == recentQuestID }, "未超过 30 天的已删除任务重启后仍应出现在已删除任务视图中")

    // --- 删除任务后详情面板应回到空态 ---
    let detailQuestID = deletionStore.addQuest(goalID: nil)
    require(deletionStore.detailTarget(for: detailQuestID.uuidString, in: .all, now: anchor, calendar: calendar) == .quest(detailQuestID), "删除前应能通过任务 ID 打开详情")
    deletionStore.deleteQuest(id: detailQuestID)
    require(deletionStore.detailTarget(for: detailQuestID.uuidString, in: .all, now: anchor, calendar: calendar) == nil, "删除任务后详情面板应回到空态（detailTarget 返回 nil）")
    deletionStore.restoreQuest(id: detailQuestID)
    require(deletionStore.detailTarget(for: detailQuestID.uuidString, in: .all, now: anchor, calendar: calendar) == .quest(detailQuestID), "恢复任务后详情面板应能重新打开")

    let detailRecurringID = deletionStore.addQuest(goalID: nil)
    deletionStore.updateQuest(id: detailRecurringID) { quest in
        quest.startDate = jan10
        quest.recurrenceRule = .daily
    }
    require(deletionStore.detailTarget(for: detailRecurringID.uuidString, in: .nextThreeDays, now: anchor, calendar: calendar) == .quest(detailRecurringID), "删除前重复任务父任务详情应可打开")
    deletionStore.deleteQuest(id: detailRecurringID)
    require(deletionStore.detailTarget(for: detailRecurringID.uuidString, in: .nextThreeDays, now: anchor, calendar: calendar) == nil, "删除重复任务父任务后详情面板应回到空态")

    // --- 已删除任务视图（回收站）：按删除时间倒序，不受时间筛选影响 ---
    let trashStorageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("questlist.json")
    let trashStore = QuestStore(storageURL: trashStorageURL)
    require(trashStore.deletedQuests().isEmpty, "没有已删除任务时回收站应为空")

    let trashFirstID = trashStore.addQuest(goalID: nil)
    trashStore.updateQuest(id: trashFirstID) { quest in
        quest.title = "最早删除"
        quest.category = .main
        quest.startDate = jan13
    }
    let trashSecondID = trashStore.addQuest(goalID: nil)
    trashStore.updateQuest(id: trashSecondID) { quest in
        quest.title = "最新删除"
        quest.category = .side
        quest.startDate = jan10
    }
    let trashUntouchedID = trashStore.addQuest(goalID: nil)
    trashStore.updateQuest(id: trashUntouchedID) { quest in
        quest.title = "未删除"
        quest.startDate = jan10
    }

    trashStore.deleteQuest(id: trashFirstID)
    trashStore.deleteQuest(id: trashSecondID)
    require(trashStore.deletedQuests().map(\.title) == ["最新删除", "最早删除"], "回收站应按删除时间倒序展示")
    require(!trashStore.deletedQuests().contains { $0.id == trashUntouchedID }, "未删除任务不应出现在回收站中")
    require(trashStore.deletedQuests().first { $0.id == trashFirstID }?.category == .main, "回收站中任务应保留其原有分类便于展示")

    trashStore.restoreQuest(id: trashFirstID)
    require(!trashStore.deletedQuests().contains { $0.id == trashFirstID }, "恢复后任务应从回收站中消失")
    require(trashStore.listItems(in: .all).contains { $0.questID == trashFirstID }, "恢复后任务应重新出现在常规列表中")

    let trashRecurringID = trashStore.addQuest(goalID: nil)
    trashStore.updateQuest(id: trashRecurringID) { quest in
        quest.title = "可删除的重复父任务"
        quest.startDate = jan10
        quest.recurrenceRule = .daily
    }
    trashStore.deleteQuest(id: trashRecurringID)
    require(trashStore.deletedQuests().filter { $0.id == trashRecurringID }.count == 1, "重复任务父任务在回收站中应作为单一整体展示，不展开 occurrence")

    // --- 端到端：删除/恢复跨重启一致性（已完成任务） ---
    let e2eStorageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("questlist.json")
    let e2eStore = QuestStore(storageURL: e2eStorageURL)
    let e2eCompletedID = e2eStore.addQuest(goalID: nil)
    e2eStore.updateQuest(id: e2eCompletedID) { quest in
        quest.title = "端到端已完成任务"
        quest.category = .main
        quest.startDate = jan10
    }
    e2eStore.completeQuest(id: e2eCompletedID)
    let completedAtBeforeDelete = e2eStore.quest(id: e2eCompletedID)?.completedAt
    e2eStore.addLog(questID: e2eCompletedID, content: "端到端过程记录")
    e2eStore.deleteQuest(id: e2eCompletedID)

    let e2eReloadedAfterDelete = QuestStore(storageURL: e2eStorageURL)
    require(e2eReloadedAfterDelete.deletedQuests().contains { $0.id == e2eCompletedID }, "重启后已删除任务应仍出现在已删除任务视图中")
    require(!e2eReloadedAfterDelete.listItems(in: .all).contains { $0.questID == e2eCompletedID }, "重启后已删除任务仍应从常规列表隐藏")
    require(e2eReloadedAfterDelete.quest(id: e2eCompletedID)?.category == .main, "重启后已删除任务应保留原分类")
    require(e2eReloadedAfterDelete.quest(id: e2eCompletedID)?.isCompleted == true, "重启后已删除任务完成状态应保持")
    require(datesAreApproximatelyEqual(e2eReloadedAfterDelete.quest(id: e2eCompletedID)?.completedAt, completedAtBeforeDelete), "重启后已删除任务完成时间应保持不变")
    require(e2eReloadedAfterDelete.logs(for: e2eCompletedID).map(\.content) == ["端到端过程记录"], "重启后已删除任务的过程记录应保留")
    let xpAfterReloadBeforeRestore = e2eReloadedAfterDelete.profile.totalXP

    e2eReloadedAfterDelete.restoreQuest(id: e2eCompletedID)
    let e2eReloadedAfterRestore = QuestStore(storageURL: e2eStorageURL)
    require(e2eReloadedAfterRestore.listItems(in: .all).contains { $0.questID == e2eCompletedID }, "重启后恢复的任务应重新出现在常规列表中")
    require(!e2eReloadedAfterRestore.deletedQuests().contains { $0.id == e2eCompletedID }, "重启后恢复的任务不应再出现在已删除任务视图中")
    require(e2eReloadedAfterRestore.quest(id: e2eCompletedID)?.isCompleted == true, "重启后恢复的任务完成状态应保持不变")
    require(datesAreApproximatelyEqual(e2eReloadedAfterRestore.quest(id: e2eCompletedID)?.completedAt, completedAtBeforeDelete), "重启后恢复的任务完成时间应保持不变")
    require(e2eReloadedAfterRestore.profile.totalXP == xpAfterReloadBeforeRestore, "重启并恢复任务不应重复发放或扣减 XP")

    // --- 端到端：occurrence override 在删除/恢复重复任务后应保持不变 ---
    let e2eOverrideStorageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("questlist.json")
    let e2eOverrideStore = QuestStore(storageURL: e2eOverrideStorageURL)
    let e2eRecurringID = e2eOverrideStore.addQuest(goalID: nil)
    e2eOverrideStore.updateQuest(id: e2eRecurringID) { quest in
        quest.title = "端到端重复任务"
        quest.category = .daily
        quest.startDate = jan10
        quest.recurrenceRule = .daily
    }
    e2eOverrideStore.applyOccurrenceOverride(
        parentQuestID: e2eRecurringID,
        date: jan10OccurrenceDate,
        scope: .once,
        override: QuestOccurrenceOverride(title: "端到端仅这一次", category: .main)
    )
    e2eOverrideStore.applyOccurrenceOverride(
        parentQuestID: e2eRecurringID,
        date: jan11OccurrenceDate,
        scope: .future,
        override: QuestOccurrenceOverride(title: "端到端之后全部", category: .side)
    )

    e2eOverrideStore.deleteQuest(id: e2eRecurringID)
    require(!e2eOverrideStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).contains { $0.questID == e2eRecurringID }, "删除重复任务父任务后 occurrence 应从视图隐藏")

    e2eOverrideStore.restoreQuest(id: e2eRecurringID)
    let restoredOverrideItems = e2eOverrideStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).filter { $0.questID == e2eRecurringID && $0.isOccurrence }
    require(restoredOverrideItems.map(\.title) == ["端到端仅这一次", "端到端之后全部", "端到端之后全部"], "恢复重复任务后 occurrence override 标题应保持不变")
    require(restoredOverrideItems.map(\.category) == [.main, .side, .side], "恢复重复任务后 occurrence override 分类应保持不变")

    let e2eOverrideReloaded = QuestStore(storageURL: e2eOverrideStorageURL)
    let reloadedOverrideItems = e2eOverrideReloaded.listItems(in: .nextThreeDays, now: anchor, calendar: calendar).filter { $0.questID == e2eRecurringID && $0.isOccurrence }
    require(reloadedOverrideItems.map(\.title) == ["端到端仅这一次", "端到端之后全部", "端到端之后全部"], "重启后 occurrence override 仍应保持")
    require(reloadedOverrideItems.map(\.category) == [.main, .side, .side], "重启后 occurrence override 分类仍应保持")
}

do {
    try runChecks()
    print("QuestListCore checks passed")
} catch {
    fputs("Check error: \(error)\n", stderr)
    exit(1)
}
