# Completed Tasks View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move completed tasks out of the main task list into a left-sidebar 「已完成任务」 view with its own independent time filter.

**Architecture:** Keep this as a SwiftUI UI-architecture change and reuse existing Core projection APIs. `ContentView` adds a completed-tasks navigation case and detail filter context, `QuestListView` becomes active-task-only, and a new `CompletedTasksView` owns its own `completedTimeFilter` state while still using `QuestStore.listItems(in:)`.

**Tech Stack:** Swift, SwiftUI, SwiftPM, existing `QuestListCoreChecks` executable.

---

## File Structure

- Modify: `apps/QuestList/Sources/QuestList/QuestListApp.swift`
  - Add `SidebarSelection.completedTasks`.
  - Add left-sidebar entry for 「已完成任务」.
  - Add detail filter context state so selected completed occurrences resolve against the completed view's private filter.
  - Remove `completedGroups` from `QuestListView` and the main list.
  - Add `CompletedTasksView`.
- Modify: `docs/superpowers/specs/2026-07-15-completed-tasks-view-design.md`
  - Already created; no implementation changes expected unless design review finds ambiguity.
- No Core model changes expected.

---

### Task 1: Navigation and Detail Filter Context

**Files:**
- Modify: `apps/QuestList/Sources/QuestList/QuestListApp.swift`

- [ ] **Step 1: Add a completed-tasks selection case**

Update `SidebarSelection` so it includes `completedTasks` after `allQuests`:

```swift
enum SidebarSelection: Hashable {
    case allQuests
    case completedTasks
    case recurringTasks
    case trash
    case timeline
    case goal(UUID)
}
```

Update `baseQuests` so the switch compiles:

```swift
    private var baseQuests: [Quest] {
        switch selection {
        case .goal(let goalID):
            store.quests.filter { $0.goalID == goalID }
        case .allQuests, .completedTasks, .recurringTasks, .trash, .timeline, .none:
            store.quests
        }
    }
```

- [ ] **Step 2: Add detail filter context state**

Add a separate state beside `selectedTimeFilter`:

```swift
    @State private var selectedTimeFilter: QuestTimeFilter = .today
    @State private var detailTimeFilter: QuestTimeFilter = .today
```

Replace the detail resolver call:

```swift
            if let selectedItemID, let target = store.detailTarget(for: selectedItemID, in: detailTimeFilter) {
```

- [ ] **Step 3: Add sidebar entry and title**

In the sidebar 「视图」 section, insert the completed-tasks entry after 「全部任务」:

```swift
                Label("全部任务", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSelection.allQuests)
                Label("已完成任务", systemImage: "checkmark.seal")
                    .tag(SidebarSelection.completedTasks)
                Label("重复任务", systemImage: "repeat")
                    .tag(SidebarSelection.recurringTasks)
```

Update `listTitle`:

```swift
    private var listTitle: String {
        switch selection {
        case .goal(let goalID):
            store.goal(id: goalID)?.name ?? "目标"
        case .completedTasks:
            "已完成任务"
        case .recurringTasks:
            "重复任务"
        case .trash:
            "已删除任务"
        default:
            "全部任务"
        }
    }
```

- [ ] **Step 4: Keep detail context in sync for main-list selections**

When building `QuestListView`, pass an `onSelectItem` closure:

```swift
                QuestListView(
                    store: store,
                    mainGroups: mainGroups,
                    sideGroups: sideGroups,
                    dailyGroups: dailyGroups,
                    selectedTimeFilter: $selectedTimeFilter,
                    selectedItemID: $selectedItemID,
                    onAddQuest: addQuest,
                    onSelectItem: {
                        detailTimeFilter = selectedTimeFilter
                    }
                )
```

Update the `QuestListView` stored properties:

```swift
struct QuestListView: View {
    @ObservedObject var store: QuestStore
    let mainGroups: [QuestItemDateGroup]
    let sideGroups: [QuestItemDateGroup]
    let dailyGroups: [QuestItemDateGroup]
    @Binding var selectedTimeFilter: QuestTimeFilter
    @Binding var selectedItemID: String?
    let onAddQuest: () -> Void
    let onSelectItem: () -> Void
```

Use the closure on row selection by adding this modifier to the `List`:

```swift
                List(selection: $selectedItemID) {
                    QuestSection(title: "主线任务", dateGroups: mainGroups, store: store)
                    QuestSection(title: "支线任务", dateGroups: sideGroups, store: store)
                    QuestSection(title: "每日任务", dateGroups: dailyGroups, store: store)
                }
                .onChange(of: selectedItemID) { _, newValue in
                    if newValue != nil {
                        onSelectItem()
                    }
                }
```

- [ ] **Step 5: Build to verify this mechanical refactor compiles after Task 2**

Do not run yet if `QuestListView` still references `completedGroups`; Task 2 removes it.

---

### Task 2: Active-Only Main List and CompletedTasksView

**Files:**
- Modify: `apps/QuestList/Sources/QuestList/QuestListApp.swift`

- [ ] **Step 1: Remove completed groups from the main list**

In `ContentView.body`, remove:

```swift
                let completedGroups = filteredItems.filter { $0.isCompleted }.groupedByDisplayDate()
```

Do not pass `completedGroups` into `QuestListView`.

Update `QuestListView.isEmpty`:

```swift
    private var isEmpty: Bool {
        mainGroups.isEmpty && sideGroups.isEmpty && dailyGroups.isEmpty
    }
```

Remove the completed section from the main list:

```swift
                List(selection: $selectedItemID) {
                    QuestSection(title: "主线任务", dateGroups: mainGroups, store: store)
                    QuestSection(title: "支线任务", dateGroups: sideGroups, store: store)
                    QuestSection(title: "每日任务", dateGroups: dailyGroups, store: store)
                }
```

- [ ] **Step 2: Add the completed view branch in `ContentView`**

Insert a branch before `.recurringTasks`:

```swift
            } else if selection == .completedTasks {
                CompletedTasksView(
                    store: store,
                    selectedItemID: $selectedItemID,
                    onSelectItem: { filter in
                        detailTimeFilter = filter
                    }
                )
                .navigationTitle("已完成任务")
```

The surrounding order should be: timeline, completedTasks, recurringTasks, trash, else main list.

- [ ] **Step 3: Create `CompletedTasksView`**

Add this view near `QuestListView` and before `QuestSection`:

```swift
struct CompletedTasksView: View {
    @ObservedObject var store: QuestStore
    @Binding var selectedItemID: String?
    let onSelectItem: (QuestTimeFilter) -> Void
    @State private var completedTimeFilter: QuestTimeFilter = .today

    private var completedGroups: [QuestItemDateGroup] {
        store.listItems(in: completedTimeFilter)
            .filter { $0.isCompleted }
            .groupedByDisplayDate()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("已完成任务")
                    .font(.headline)
                TimeFilterPicker(selectedTimeFilter: $completedTimeFilter)
            }
            .padding()

            if completedGroups.isEmpty {
                ContentUnavailableView(
                    "暂无已完成任务",
                    systemImage: "checkmark.seal",
                    description: Text("当前时间范围内暂无已完成任务")
                )
            } else {
                List(selection: $selectedItemID) {
                    QuestSection(title: "已完成任务", dateGroups: completedGroups, store: store)
                }
                .onChange(of: selectedItemID) { _, newValue in
                    if newValue != nil {
                        onSelectItem(completedTimeFilter)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Keep completed detail context synced when its filter changes**

Add this modifier to the outer `VStack` in `CompletedTasksView`:

```swift
        .onChange(of: completedTimeFilter) { _, newValue in
            if selectedItemID != nil {
                onSelectItem(newValue)
            }
        }
```

The completed view body should end like:

```swift
        }
        .onChange(of: completedTimeFilter) { _, newValue in
            if selectedItemID != nil {
                onSelectItem(newValue)
            }
        }
```

- [ ] **Step 5: Run a build and fix compile errors**

Run:

```bash
swift build --package-path /Users/xwy/Desktop/teach/apps/QuestList
```

Expected output includes:

```text
Build complete!
```

---

### Task 3: Verification, Review, and Commit

**Files:**
- Verify: `apps/QuestList/Sources/QuestList/QuestListApp.swift`
- Verify: `docs/superpowers/specs/2026-07-15-completed-tasks-view-design.md`
- Commit if verification passes.

- [ ] **Step 1: Run CoreChecks and build**

Run:

```bash
swift run --package-path /Users/xwy/Desktop/teach/apps/QuestList QuestListCoreChecks && swift build --package-path /Users/xwy/Desktop/teach/apps/QuestList
```

Expected output includes:

```text
QuestListCore checks passed
Build complete!
```

- [ ] **Step 2: Inspect UI requirements in code**

Confirm `QuestListApp.swift` has these properties:

```swift
case completedTasks
```

```swift
Label("已完成任务", systemImage: "checkmark.seal")
```

```swift
struct CompletedTasksView: View
```

Confirm `QuestListView` no longer contains:

```swift
QuestSection(title: "已完成任务"
```

- [ ] **Step 3: Check Git status**

Run:

```bash
git -C /Users/xwy/Desktop/teach status --short
```

Expected tracked changes include:

```text
 M apps/QuestList/Sources/QuestList/QuestListApp.swift
?? docs/superpowers/specs/2026-07-15-completed-tasks-view-design.md
?? docs/superpowers/plans/2026-07-15-completed-tasks-view.md
```

`AGENTS.md` may remain untracked and should not be included unless the user explicitly asks.

- [ ] **Step 4: Commit the feature**

If verification passes, commit only the feature files:

```bash
git -C /Users/xwy/Desktop/teach add apps/QuestList/Sources/QuestList/QuestListApp.swift docs/superpowers/specs/2026-07-15-completed-tasks-view-design.md docs/superpowers/plans/2026-07-15-completed-tasks-view.md
git -C /Users/xwy/Desktop/teach commit -m "feat: add completed tasks view"
```

- [ ] **Step 5: Do not push unless explicitly requested**

After commit, report the commit hash and verification result. Do not run `git push` unless the user asks for it.

---

## Self-Review

- **Spec coverage:** The plan covers the left-sidebar entry, removal of completed tasks from the main list, an independent completed-task filter state, completed ordinary/occurrence display via existing Core projections, and detail resolution using the completed view's filter context.
- **Placeholder scan:** No placeholder or vague implementation steps remain; every code-changing step contains concrete Swift snippets or exact commands.
- **Type consistency:** Uses existing names from the codebase: `SidebarSelection`, `QuestListView`, `QuestSection`, `QuestTimeFilter`, `QuestItemDateGroup`, `selectedItemID`, and `store.detailTarget(for:in:)`.
