# Future Time Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global 「未来」 time filter that shows tasks from tomorrow onward and only one next future occurrence per recurring parent task.

**Architecture:** Keep the rule in QuestListCore so 「全部任务」 and 「重复任务」 views share identical behavior through `QuestStore.listItems(in:)`. Add `.future` to `QuestTimeFilter`, make `contains` treat it as an open-ended future range, and special-case occurrence generation to return only the next matching future occurrence.

**Tech Stack:** Swift, SwiftPM, SwiftUI, existing `QuestListCoreChecks` executable.

---

## File Structure

- Modify: `apps/QuestList/Sources/QuestListCoreChecks/main.swift`
  - Adds failing checks for `.future` title, ordinary task filtering, daily/weekly/yearly recurring next occurrence behavior, and store-level one-occurrence-per-parent behavior.
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift`
  - Adds `QuestTimeFilter.future`, open-ended future containment, and next-future-occurrence generation.
- No direct UI file changes expected:
  - `TimeFilterPicker` already renders `QuestTimeFilter.allCases`, so adding `.future` makes 「未来」 appear automatically.

---

### Task 1: CoreChecks Future Filter Coverage

**Files:**
- Modify: `apps/QuestList/Sources/QuestListCoreChecks/main.swift`

- [ ] **Step 1: Add failing CoreChecks for future semantics**

Insert the following checks after the existing time-filter group assertions around the current `groups` checks:

```swift
    require(QuestTimeFilter.future.title == "未来", "时间筛选器应提供未来标题")
    let futureVisibleTitles = quests.visible(in: .future, now: anchor, calendar: calendar).map(\.title)
    require(futureVisibleTitles == ["按截止时间显示", "三天内支线", "三天外任务"], "未来应排除今天任务，包含明天及之后的任务")
```

Insert the following checks after the existing `dailyOccurrences` assertion block:

```swift
    let futureDailyOccurrences = dailyParent.generateOccurrences(in: .future, now: anchor, calendar: calendar)
    require(occurrenceDays(futureDailyOccurrences, calendar: calendar) == [11], "每日规则未来筛选应只生成下一次未来 occurrence")
```

Insert the following checks after the existing `weeklyOccurrences` assertion block:

```swift
    let futureWeeklyOccurrences = weeklyParent.generateOccurrences(in: .future, now: anchor, calendar: calendar)
    require(occurrenceDays(futureWeeklyOccurrences, calendar: calendar) == [15], "每周规则未来筛选应只生成下一次命中的 occurrence")
```

Insert the following checks after the existing yearly recurrence assertion block:

```swift
    let futureYearlyAnchor = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2024, month: 1, day: 2, hour: 12).date!
    let futureYearlyParent = Quest(title: "未来年度任务", startDate: day(2, calendar: calendar), recurrenceRule: .yearly(month: 12, day: 31))
    let futureYearlyOccurrences = futureYearlyParent.generateOccurrences(in: .future, now: futureYearlyAnchor, calendar: calendar)
    require(occurrenceMonthDays(futureYearlyOccurrences, calendar: calendar) == ["12-31"], "年度规则未来筛选应能找到一年内下一次命中")
```

Insert the following store-level checks after `projectedItems` / `recurringItems` assertions:

```swift
    let futureProjectedItems = store.listItems(in: .future, now: anchor, calendar: calendar)
    let futureRecurringItems = futureProjectedItems.filter { $0.questID == recurringQuestID && $0.isOccurrence }
    require(futureRecurringItems.map { calendar.component(.day, from: $0.displayDate) } == [11], "Store 未来筛选下每个重复父任务只应投影下一次 occurrence")
```

- [ ] **Step 2: Run CoreChecks and verify the expected failure**

Run:

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

Expected: build fails because `QuestTimeFilter.future` does not exist yet.

---

### Task 2: Implement Future Filter in Core

**Files:**
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift`

- [ ] **Step 1: Add `.future` to `QuestTimeFilter`**

Change the enum cases to include `.future` before `.all`:

```swift
public enum QuestTimeFilter: String, CaseIterable, Identifiable, Hashable {
    case today
    case nextThreeDays
    case nextWeek
    case nextMonth
    case future
    case all
```

Update `title`:

```swift
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
```

- [ ] **Step 2: Add open-ended future containment**

Replace `contains(_:now:calendar:)` with:

```swift
    public func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        if self == .future {
            return date >= futureStart(now: now, calendar: calendar)
        }
        guard let interval = dateInterval(now: now, calendar: calendar) else { return true }
        return date >= interval.start && date < interval.end
    }
```

Update `dateInterval(now:calendar:)` so `.future` behaves like `.all` for finite intervals:

```swift
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
```

Add this helper inside the `QuestTimeFilter` enum:

```swift
    public func futureStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        let todayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
    }
```

- [ ] **Step 3: Special-case recurring occurrence generation**

At the top of `Quest.generateOccurrences(in:now:calendar:)`, after the `guard let recurrenceRule else { return [] }` line, add:

```swift
        if timeFilter == .future {
            return nextFutureOccurrence(recurrenceRule: recurrenceRule, now: now, calendar: calendar)
        }
```

Add this private method in the same `Quest` extension, before `generationEnd(for:now:calendar:)`:

```swift
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
```

- [ ] **Step 4: Run CoreChecks and verify pass**

Run:

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

Expected output includes:

```text
QuestListCore checks passed
```

---

### Task 3: Build Regression and UI Sanity

**Files:**
- No additional source modifications expected.

- [ ] **Step 1: Build the package**

Run:

```bash
swift build --package-path /Users/xwy/Desktop/teach/apps/QuestList
```

Expected output includes:

```text
Build complete!
```

- [ ] **Step 2: Confirm UI hookup by code inspection**

Verify `apps/QuestList/Sources/QuestList/QuestListApp.swift` still renders the time filter through all cases:

```swift
ForEach(QuestTimeFilter.allCases) { filter in
    Text(filter.title).tag(filter)
}
```

Expected: no UI-specific branch is required; 「未来」 appears automatically because `.future` is part of `CaseIterable`.

- [ ] **Step 3: Version control handling**

If this workspace is still not a Git repository, skip commit and report that explicitly. If it is a Git repository, commit only the plan/spec/core/check changes with:

```bash
git add docs/superpowers/specs/2026-07-13-future-time-filter-design.md docs/superpowers/plans/2026-07-13-future-time-filter.md apps/QuestList/Sources/QuestListCore/QuestListCore.swift apps/QuestList/Sources/QuestListCoreChecks/main.swift
git commit -m "feat: add future time filter"
```

---

## Self-Review

- **Spec coverage:** Covered `.future` title, tomorrow-start semantics, ordinary task filtering, recurring next occurrence behavior, shared Core result for both views, and verification commands.
- **Placeholder scan:** No placeholder steps remain; each code-changing step includes concrete snippets and exact commands.
- **Type consistency:** Uses existing `QuestTimeFilter`, `Quest.generateOccurrences`, `QuestRecurrenceRule`, `QuestOccurrence`, `visible(in:)`, and `listItems(in:)` names consistently with the current codebase.
