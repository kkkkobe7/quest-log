# 新建任务空标题与任务级经验值自定义 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新建任务标题默认为空字符串，并支持每个任务单独自定义 XP，occurrence 可覆盖 XP。

**Architecture:** 在 `Quest` 新增 `baseXPReward: Int` 存储任务级 XP，与难度枚举解耦；`QuestOccurrenceOverride` 新增 `xpReward: Int?`；UI 层对空标题统一 fallback 为"未命名任务"，并在详情页新增"经验值"输入行。

**Tech Stack:** Swift 5.9, SwiftUI (macOS), SwiftPM, QuestListCoreChecks（自定义检查可执行文件）

---

## 文件映射

- **Modify:** `apps/QuestList/Sources/QuestListCore/QuestListCore.swift`
- **Modify:** `apps/QuestList/Sources/QuestListCoreChecks/main.swift`
- **Modify:** `apps/QuestList/Sources/QuestList/QuestListApp.swift`

---

### Task 1: Core — Quest 新增 baseXPReward 字段，空标题，JSON 兼容

**Files:**
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift`
- Modify: `apps/QuestList/Sources/QuestListCoreChecks/main.swift`

- [ ] **Step 1.1: 先写失败测试**

在 `main.swift` 的 `runChecks()` 函数末尾（删除任务相关 block 之前）添加如下测试块：

```swift
// --- 空标题与任务级 XP ---
let xpStorageURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
    .appendingPathComponent("questlist.json")
let xpStore = QuestStore(storageURL: xpStorageURL)

// 新建任务标题默认为空
let emptyTitleID = xpStore.addQuest(goalID: nil)
require(xpStore.quest(id: emptyTitleID)?.title == "", "新建任务标题应默认为空字符串")

// 空标题展示 fallback
let emptyQuest = Quest(title: "")
require(emptyQuest.displayTitle == "未命名任务", "空标题应展示 fallback '未命名任务'")
let namedQuest = Quest(title: "读书")
require(namedQuest.displayTitle == "读书", "非空标题应原样展示")

// 任务级 XP：新建时使用默认难度（普通=25）的默认值
let xpQuestID = xpStore.addQuest(goalID: nil)
require(xpStore.quest(id: xpQuestID)?.baseXPReward == 25, "新建任务 baseXPReward 应使用默认难度普通=25")

// 用户自定义 XP
xpStore.updateQuest(id: xpQuestID) { quest in
    quest.baseXPReward = 80
}
require(xpStore.quest(id: xpQuestID)?.baseXPReward == 80, "baseXPReward 应支持自定义")

// 完成后按自定义 XP 发放
let xpBeforeCustom = xpStore.profile.totalXP
xpStore.completeQuest(id: xpQuestID)
require(xpStore.profile.totalXP == xpBeforeCustom + 80, "完成任务应按 baseXPReward 发放 XP，而不是 difficulty.xpReward")

// 旧 JSON 兼容（缺少 baseXPReward 字段）
let oldJsonData = Data("""
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
let decodedOldQuest = try JSONDecoder.questList.decode(Quest.self, from: oldJsonData)
require(decodedOldQuest.baseXPReward == 50, "旧 JSON 缺少 baseXPReward 时应回退为 difficulty.xpReward（困难=50）")
```

- [ ] **Step 1.2: 运行确认红灯**

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

预期：编译报错，`Quest` 无 `displayTitle`、`baseXPReward` 成员。

- [ ] **Step 1.3: 实现 Quest.displayTitle 计算属性**

在 `QuestListCore.swift` 的 `Quest` struct 内，`xpReward` 计算属性下方添加：

```swift
public var displayTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名任务" : title
}
```

- [ ] **Step 1.4: 实现 Quest.baseXPReward 存储属性**

在 `Quest` struct 的属性声明区（`deletedAt` 下方）添加存储属性：

```swift
public var baseXPReward: Int
```

在 `Quest.init()` 参数列表（`deletedAt: Date? = nil` 之后）添加：

```swift
baseXPReward: Int? = nil,
```

在 init body 的赋值区（`self.deletedAt = deletedAt` 之后）添加：

```swift
self.baseXPReward = baseXPReward ?? difficulty.xpReward
```

在 `CodingKeys` 枚举末尾添加：

```swift
case baseXPReward
```

在 `init(from decoder:)` 末尾（`self.deletedAt = ...` 之后）添加：

```swift
self.baseXPReward = try container.decodeIfPresent(Int.self, forKey: .baseXPReward) ?? difficulty.xpReward
```

在 `encode(to encoder:)` 末尾添加：

```swift
try container.encode(baseXPReward, forKey: .baseXPReward)
```

- [ ] **Step 1.5: 修改 Quest.xpReward 计算属性**

将：

```swift
public var xpReward: Int { difficulty.xpReward }
```

改为：

```swift
public var xpReward: Int { baseXPReward }
```

（此后所有依赖 `quest.xpReward` 的地方自动使用 `baseXPReward`。）

- [ ] **Step 1.6: 修改 addQuest() 使用空标题**

将：

```swift
let quest = Quest(title: "新建任务", goalID: goalID)
```

改为：

```swift
let quest = Quest(title: "", goalID: goalID)
```

- [ ] **Step 1.7: 修改 Quest 解码中 title 的 fallback**

将：

```swift
self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "新建任务"
```

改为：

```swift
self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
```

- [ ] **Step 1.8: 运行确认绿灯**

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

预期：`QuestListCore checks passed`

---

### Task 2: Core — occurrence 继承与覆盖 XP

**Files:**
- Modify: `apps/QuestList/Sources/QuestListCore/QuestListCore.swift`
- Modify: `apps/QuestList/Sources/QuestListCoreChecks/main.swift`

- [ ] **Step 2.1: 先写失败测试**

在 Task 1 新增的测试块末尾（`require(decodedOldQuest.baseXPReward == 50, ...)` 之后，现有 `// --- 已删除任务` 块之前）添加：

```swift
// occurrence 继承与覆盖 XP
let xpRecurringID = xpStore.addQuest(goalID: nil)
xpStore.updateQuest(id: xpRecurringID) { quest in
    quest.title = "XP重复任务"
    quest.startDate = jan10
    quest.recurrenceRule = .daily
    quest.baseXPReward = 60
}
let occurrenceItems = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
    .filter { $0.questID == xpRecurringID && $0.isOccurrence }
require(occurrenceItems.allSatisfy { $0.xpReward == 60 }, "occurrence 默认应继承父任务 baseXPReward")

// 仅这一次 override XP
xpStore.applyOccurrenceOverride(
    parentQuestID: xpRecurringID,
    date: jan10OccurrenceDate,
    scope: .once,
    override: QuestOccurrenceOverride(xpReward: 99)
)
let jan10Item = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
    .first { $0.questID == xpRecurringID && calendar.isDate($0.displayDate, inSameDayAs: jan10) }
require(jan10Item?.xpReward == 99, "仅这一次 XP override 应生效")
let jan11Item = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
    .first { $0.questID == xpRecurringID && calendar.isDate($0.displayDate, inSameDayAs: jan11) }
require(jan11Item?.xpReward == 60, "仅这一次 XP override 不影响其他 occurrence")

// 之后全部 override XP
xpStore.applyOccurrenceOverride(
    parentQuestID: xpRecurringID,
    date: jan11OccurrenceDate,
    scope: .future,
    override: QuestOccurrenceOverride(xpReward: 77)
)
let jan11ItemAfterFuture = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
    .first { $0.questID == xpRecurringID && calendar.isDate($0.displayDate, inSameDayAs: jan11) }
require(jan11ItemAfterFuture?.xpReward == 77, "之后全部 XP override 应生效")
let jan10ItemAfterFuture = xpStore.listItems(in: .nextThreeDays, now: anchor, calendar: calendar)
    .first { $0.questID == xpRecurringID && calendar.isDate($0.displayDate, inSameDayAs: jan10) }
require(jan10ItemAfterFuture?.xpReward == 99, "之后全部 XP override 不影响有独立 once override 的 occurrence")
require(xpStore.quest(id: xpRecurringID)?.baseXPReward == 60, "occurrence XP override 不应修改父任务 baseXPReward")

// 完成带 XP override 的 occurrence 按 override 值发放
let xpBeforeOccurrence = xpStore.profile.totalXP
xpStore.completeOccurrence(parentQuestID: xpRecurringID, date: jan10OccurrenceDate)
require(xpStore.profile.totalXP == xpBeforeOccurrence + 99, "完成 occurrence 应按当前投影 XP 发放（含 once override）")
```

- [ ] **Step 2.2: 运行确认红灯**

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

预期：编译报错，`QuestOccurrenceOverride.init` 没有 `xpReward` 参数。

- [ ] **Step 2.3: QuestOccurrenceOverride 新增 xpReward 字段**

在 `QuestOccurrenceOverride` struct 内，`dueDate: Date?` 之后添加：

```swift
public var xpReward: Int?
```

在 `init(title:reward:category:difficulty:dueDate:)` 参数列表末尾添加：

```swift
xpReward: Int? = nil
```

在 init body 末尾添加：

```swift
self.xpReward = xpReward
```

在 `merging(_:)` 方法的返回值中添加 `xpReward: override.xpReward ?? xpReward`：

```swift
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
```

- [ ] **Step 2.4: QuestListItem 使用 override xpReward**

找到 `QuestListItem` 的 `init(parent:occurrence:state:override:)` 里 `self.xpReward` 相关赋值。当前 `xpReward` 是 `QuestListItem` 的计算属性 `var xpReward: Int { difficulty.xpReward }`。

将 `QuestListItem` 的 `xpReward` 从计算属性改为存储属性：

在 `QuestListItem` 的属性声明区（`goalID: UUID?` 之后）添加：

```swift
public var xpReward: Int
```

（删除原来的计算属性 `public var xpReward: Int { difficulty.xpReward }`）

在 `init(quest: Quest)` body 末尾添加：

```swift
self.xpReward = quest.baseXPReward
```

（其中 `quest.xpReward` 即等于 `quest.baseXPReward`，二者已统一。）

在 `init(parent:occurrence:state:override:)` body 末尾添加：

```swift
self.xpReward = override?.xpReward ?? parent.baseXPReward
```

- [ ] **Step 2.5: 运行确认绿灯**

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

预期：`QuestListCore checks passed`

---

### Task 3: UI — 列表行 & 回收站行空标题 fallback，详情页经验值输入行

**Files:**
- Modify: `apps/QuestList/Sources/QuestList/QuestListApp.swift`

- [ ] **Step 3.1: 列表行 QuestRow 使用 displayTitle**

在 `QuestListApp.swift` 中找到 `QuestRow` 里显示任务标题的 `Text(item.title)`（出现在 VStack 内），改为：

```swift
Text(item.title.isEmpty ? "未命名任务" : item.title)
    .foregroundStyle(item.title.isEmpty ? .secondary : .primary)
```

- [ ] **Step 3.2: TrashRow 使用 displayTitle**

在 `TrashRow` 里找到 `Text(quest.title)`，改为：

```swift
Text(quest.title.isEmpty ? "未命名任务" : quest.title)
    .foregroundStyle(quest.title.isEmpty ? .secondary : .primary)
```

- [ ] **Step 3.3: 任务详情页新增经验值输入行**

在 `QuestDetailView` 内：

1. 在 `@State private var draftReward = ""` 下方新增：

```swift
@State private var draftXPReward = ""
```

2. 在 `syncDraftFields(from:)` 方法内，`draftReward = quest.reward` 之后添加：

```swift
draftXPReward = String(quest.baseXPReward)
```

3. 在 `Form { Section("任务") { ... } }` 内，难度 `Picker` 下方紧跟新增经验值输入行：

```swift
EditableTextRow(title: "经验值", placeholder: "输入经验值（正整数）", text: $draftXPReward)
    .onChange(of: draftXPReward) { _, newValue in
        if let xp = Int(newValue), xp >= 0 {
            store.updateQuest(id: questID) { quest in
                quest.baseXPReward = xp
            }
        }
    }
```

- [ ] **Step 3.4: occurrence 详情页新增经验值输入行**

在 `OccurrenceDetailView` 内：

1. 在 `@State private var draftDifficulty: QuestDifficulty = .medium` 下方新增：

```swift
@State private var draftXPReward = ""
```

2. 在 `syncDraftFields()` 内，`draftDueDate = item.displayDate` 之后添加：

```swift
draftXPReward = String(item.xpReward)
```

3. 在 occurrence Form Section 内，难度 Picker 下方添加：

```swift
EditableTextRow(title: "经验值", placeholder: "输入经验值（正整数）", text: $draftXPReward)
```

4. 在 `applyOverride(scope:)` 方法的 `QuestOccurrenceOverride(...)` 初始化调用中，在 `dueDate: draftDueDate` 之后添加：

```swift
xpReward: Int(draftXPReward)
```

- [ ] **Step 3.5: 编译验证**

```bash
swift build --package-path /Users/xwy/Desktop/teach/apps/QuestList
```

预期：`Build complete!`

- [ ] **Step 3.6: 完整验证**

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks
```

预期：`QuestListCore checks passed`
