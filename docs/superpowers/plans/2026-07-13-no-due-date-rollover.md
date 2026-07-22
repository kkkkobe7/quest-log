# 无截止时间任务默认延续 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让无截止时间的未完成普通任务自动延续到今天，完成后按完成日期停止延续。

**Architecture:** 在 Core 层新增统一的 `effectiveDisplayDate(now:calendar:)` 计算，并让 `QuestStore.listItems` 与 `QuestListItem` 使用同一份结果。原始 `startDate` 保持不动，滚动只发生在列表投影阶段。

**Tech Stack:** Swift, SwiftPM, SwiftUI, QuestListCoreChecks

---

## File Structure

- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift`
  - 新增无截止时间任务的有效显示日期计算。
  - 让普通任务筛选、列表投影、`QuestListItem.displayDate` 和 `[Quest]` 辅助分组使用一致语义。
  - 让重新完成任务更新 `completedAt`，但不重复发放 XP。
- Modify: `apps/QuestList/Sources/QuestListCoreChecks/main.swift`
  - 增加无截止时间任务滚动、未来开始、完成日期、取消完成、重新完成与 XP 防重检查。

不修改 SwiftUI 文件；「全部任务」「已完成任务」「目标视图」会自然使用 Core 返回的统一 `QuestListItem.displayDate`。

---

### Task 1: 为无截止时间任务滚动写失败检查

**Files:**
- Modify: `apps/QuestList/Sources/QuestListCoreChecks/main.swift:103-106`

- [ ] **Step 1: 在现有未来筛选检查后插入滚动检查**

在 `require(futureVisibleTitles == ...)` 之后插入：

```swift
    // --- 无截止时间任务：未完成延续，完成停止 ---
    let rolloverStorageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("questlist.json")
    let rolloverStore = QuestStore(storageURL: rolloverStorageURL)
    let yesterdayStart = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 9, hour: 15, minute: 30).date!
    let yesterdayCompletion = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 9, hour: 16).date!
    let legacyStart = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 8, hour: 10).date!
    let futureNoDueStart = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 11, hour: 9).date!
    let overdueDueDate = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 9, hour: 18).date!

    let rolloverQuestID = rolloverStore.addQuest(goalID: nil)
    rolloverStore.updateQuest(id: rolloverQuestID) { quest in
        quest.title = "昨天延续"
        quest.startDate = yesterdayStart
    }
    let futureNoDueQuestID = rolloverStore.addQuest(goalID: nil)
    rolloverStore.updateQuest(id: futureNoDueQuestID) { quest in
        quest.title = "明天开始"
        quest.startDate = futureNoDueStart
    }
    let overdueDueQuestID = rolloverStore.addQuest(goalID: nil)
    rolloverStore.updateQuest(id: overdueDueQuestID) { quest in
        quest.title = "过期截止"
        quest.startDate = jan10
        quest.dueDate = overdueDueDate
    }
    let completedNoDueQuestID = rolloverStore.addQuest(goalID: nil)
    rolloverStore.updateQuest(id: completedNoDueQuestID) { quest in
        quest.title = "昨天完成"
        quest.startDate = legacyStart
        quest.isCompleted = true
        quest.completedAt = yesterdayCompletion
    }
    let legacyCompletedQuestID = rolloverStore.addQuest(goalID: nil)
    rolloverStore.updateQuest(id: legacyCompletedQuestID) { quest in
        quest.title = "旧完成"
        quest.startDate = legacyStart
        quest.isCompleted = true
        quest.completedAt = nil
    }

    let rolloverTodayItems = rolloverStore.listItems(in: .today, now: anchor, calendar: calendar)
    require(rolloverTodayItems.contains { $0.questID == rolloverQuestID }, "昨天开始且未完成的无截止任务应滚到今日视图")
    require(!rolloverTodayItems.contains { $0.questID == futureNoDueQuestID }, "未来开始的无截止任务不应提前进入今日视图")
    require(!rolloverTodayItems.contains { $0.questID == overdueDueQuestID }, "有截止时间的过期任务不应滚到今日视图")
    require(!rolloverTodayItems.contains { $0.questID == completedNoDueQuestID }, "已完成的无截止任务不应继续滚到今日视图")
    require(!rolloverTodayItems.contains { $0.questID == legacyCompletedQuestID }, "缺少 completedAt 的旧已完成任务不应滚到今日视图")

    let rolledItem = rolloverTodayItems.first { $0.questID == rolloverQuestID }
    require(calendar.component(.day, from: rolledItem?.displayDate ?? .distantPast) == 10, "滚动后的日期部分应为今天")
    require(calendar.component(.hour, from: rolledItem?.displayDate ?? .distantPast) == 15, "滚动后应保留原开始时间的小时")
    require(calendar.component(.minute, from: rolledItem?.displayDate ?? .distantPast) == 30, "滚动后应保留原开始时间的分钟")

    let rolloverAllItems = rolloverStore.listItems(in: .all, now: anchor, calendar: calendar)
    let completedItem = rolloverAllItems.first { $0.questID == completedNoDueQuestID }
    let legacyCompletedItem = rolloverAllItems.first { $0.questID == legacyCompletedQuestID }
    let dueItem = rolloverAllItems.first { $0.questID == overdueDueQuestID }
    require(calendar.component(.day, from: completedItem?.displayDate ?? .distantPast) == 9, "已完成无截止任务应按 completedAt 分组")
    require(calendar.component(.hour, from: completedItem?.displayDate ?? .distantPast) == 16, "已完成无截止任务应保留 completedAt 时间")
    require(calendar.component(.day, from: legacyCompletedItem?.displayDate ?? .distantPast) == 8, "缺少 completedAt 的旧已完成任务应回退到 startDate")
    require(calendar.component(.day, from: dueItem?.displayDate ?? .distantPast) == 9, "有截止时间的任务仍应按 dueDate 分组")
    require(rolloverStore.listItems(in: .future, now: anchor, calendar: calendar).contains { $0.questID == futureNoDueQuestID }, "未来开始的无截止任务应出现在未来筛选")
    require(!rolloverStore.listItems(in: .future, now: anchor, calendar: calendar).contains { $0.questID == rolloverQuestID }, "滚到今天的无截止任务不应出现在未来筛选")

    rolloverStore.updateQuest(id: completedNoDueQuestID) { quest in
        quest.isCompleted = false
    }
    require(rolloverStore.listItems(in: .today, now: anchor, calendar: calendar).contains { $0.questID == completedNoDueQuestID }, "取消完成后无截止任务应重新滚到今日视图")
```

- [ ] **Step 2: 运行检查确认失败**

Run:

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

Expected: FAIL，第一条失败信息应类似：

```text
Check failed: 昨天开始且未完成的无截止任务应滚到今日视图
```

- [ ] **Step 3: 提交失败测试**

```bash
git -C /Users/xwy/Desktop/teach add apps/QuestList/Sources/QuestListCoreChecks/main.swift
git -C /Users/xwy/Desktop/teach commit -m "test: specify no-due-date rollover"
```

---

### Task 2: 实现 Core 有效显示日期

**Files:**
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift:95-112`
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift:406-415`
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift:608-657`
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift:847-871`

- [ ] **Step 1: 给 Quest 增加有效显示日期**

把：

```swift
    public var displayDate: Date {
        dueDate ?? startDate
    }
```

保留不动，并在它后面新增：

```swift
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
```

`displayDate` 保留为原始显示语义，兼容现有直接读取；列表投影使用 `effectiveDisplayDate`。

- [ ] **Step 2: 让 listItems 使用有效显示日期**

把 `listItems` 中普通任务分支：

```swift
            guard timeFilter.contains(quest.displayDate, now: now, calendar: calendar) else { return [] }
            return [QuestListItem(quest: quest)]
```

替换为：

```swift
            let displayDate = quest.effectiveDisplayDate(now: now, calendar: calendar)
            guard timeFilter.contains(displayDate, now: now, calendar: calendar) else { return [] }
            return [QuestListItem(quest: quest, now: now, calendar: calendar)]
```

- [ ] **Step 3: 让 QuestListItem 保存 Core 计算好的 displayDate**

在 `QuestListItem` 的字段区新增：

```swift
    public var displayDate: Date
```

把普通任务初始化器：

```swift
    public init(quest: Quest) {
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
    }
```

替换为：

```swift
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
```

在 occurrence 初始化器末尾 `self.xpReward = ...` 后新增：

```swift
        self.displayDate = override?.dueDate ?? occurrence.date
```

删除现有计算属性：

```swift
    public var displayDate: Date { dueDate ?? occurrenceDate ?? .now }
```

- [ ] **Step 4: 同步 [Quest] 辅助筛选和分组**

把：

```swift
    func visible(in timeFilter: QuestTimeFilter, now: Date = .now, calendar: Calendar = .current) -> [Quest] {
        filter { quest in
            timeFilter.contains(quest.displayDate, now: now, calendar: calendar)
        }
    }
```

替换为：

```swift
    func visible(in timeFilter: QuestTimeFilter, now: Date = .now, calendar: Calendar = .current) -> [Quest] {
        filter { quest in
            timeFilter.contains(quest.effectiveDisplayDate(now: now, calendar: calendar), now: now, calendar: calendar)
        }
    }
```

把 `groupedByDisplayDate` 中：

```swift
        let grouped = Dictionary(grouping: visibleQuests) { quest in
            calendar.startOfDay(for: quest.displayDate)
        }
```

替换为：

```swift
        let grouped = Dictionary(grouping: visibleQuests) { quest in
            calendar.startOfDay(for: quest.effectiveDisplayDate(now: now, calendar: calendar))
        }
```

把排序中的：

```swift
                    if lhs.displayDate != rhs.displayDate {
                        return lhs.displayDate < rhs.displayDate
                    }
```

替换为：

```swift
                    let lhsDisplayDate = lhs.effectiveDisplayDate(now: now, calendar: calendar)
                    let rhsDisplayDate = rhs.effectiveDisplayDate(now: now, calendar: calendar)
                    if lhsDisplayDate != rhsDisplayDate {
                        return lhsDisplayDate < rhsDisplayDate
                    }
```

- [ ] **Step 5: 运行检查确认通过**

Run:

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

Expected: PASS

```text
QuestListCore checks passed
```

- [ ] **Step 6: 提交 Core 滚动实现**

```bash
git -C /Users/xwy/Desktop/teach add apps/QuestList/Sources/QuestListCore/QuestListCore.swift
git -C /Users/xwy/Desktop/teach commit -m "feat: roll unfinished quests without due dates"
```

---

### Task 3: 重新完成时更新完成时间但不重复发放 XP

**Files:**
- Modify: `apps/QuestList/Sources/QuestListCoreChecks/main.swift:105-170`
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift:49-61`

- [ ] **Step 1: 写重新完成的失败检查**

在 Task 1 的取消完成检查后追加：

```swift
    let xpBeforeRolloverRecompletion = rolloverStore.profile.totalXP
    rolloverStore.updateQuest(id: rolloverQuestID) { quest in
        quest.isCompleted = false
        quest.xpAwarded = true
        quest.completedAt = yesterdayCompletion
    }
    let recompletionTime = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 10, hour: 17).date!
    rolloverStore.completeQuest(id: rolloverQuestID, now: recompletionTime)
    require(datesAreApproximatelyEqual(rolloverStore.quest(id: rolloverQuestID)?.completedAt, recompletionTime), "重新完成任务时应更新 completedAt")
    require(rolloverStore.profile.totalXP == xpBeforeRolloverRecompletion, "重新完成已发放 XP 的任务时不应重复发放 XP")
```

- [ ] **Step 2: 运行检查确认失败**

Run:

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

Expected: FAIL，编译错误应类似：

```text
error: extra argument 'now' in call
```

- [ ] **Step 3: 更新 completeQuest 签名和实现**

把：

```swift
    public func completeQuest(id: UUID) {
        updateQuest(id: id) { quest in
            guard !quest.xpAwarded else {
                quest.isCompleted = true
                return
            }
            quest.isCompleted = true
            quest.xpAwarded = true
            quest.completedAt = .now
            profile.totalXP += quest.xpReward
        }
        save()
    }
```

替换为：

```swift
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
```

默认参数保持 SwiftUI 调用方无需修改。

- [ ] **Step 4: 运行完整 CoreChecks**

Run:

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

Expected: PASS

```text
QuestListCore checks passed
```

- [ ] **Step 5: 运行完整构建**

Run:

```bash
swift build --package-path /Users/xwy/Desktop/teach/apps/QuestList
```

Expected: PASS

```text
Build complete!
```

- [ ] **Step 6: 代码审查**

使用 CodeReview 子代理审查当前未提交改动，重点确认：

- 无截止时间任务滚动只影响普通任务，不影响 occurrence。
- `QuestListItem.displayDate` 与 `listItems` 筛选使用同一语义。
- 重新完成更新 `completedAt` 但不重复加 XP。
- 已删除任务、未来筛选和完成视图没有高信号回归。

Expected: 无阻塞问题；如有问题，修复后重新运行 CoreChecks 和 build。

- [ ] **Step 7: 提交最终改动**

```bash
git -C /Users/xwy/Desktop/teach add apps/QuestList/Sources/QuestListCore/QuestListCore.swift apps/QuestList/Sources/QuestListCoreChecks/main.swift
git -C /Users/xwy/Desktop/teach commit -m "fix: refresh completion date without double xp"
```

---

## Self-Review

- Spec coverage: Task 1/2 覆盖滚动、未来开始、完成日期、旧数据回退、取消完成、dueDate 与 occurrence 不回归；Task 3 覆盖重新完成更新 `completedAt` 且 XP 防重。
- Placeholder scan: 无 TBD/TODO；每个代码步骤都包含实际代码和命令。
- Type consistency: `effectiveDisplayDate(now:calendar:)`、`QuestListItem(quest:now:calendar:)`、`completeQuest(id:now:)` 在前后任务中签名一致。
