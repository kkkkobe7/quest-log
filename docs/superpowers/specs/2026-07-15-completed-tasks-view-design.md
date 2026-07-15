# 已完成任务独立视图设计

## 背景

QuestList 当前在「全部任务」中同时展示未完成任务与底部折叠的「已完成任务」分区。随着任务数量增多，已完成内容会干扰当前待办视图；用户希望将已完成任务单独放到左侧导航栏中，并且该视图也支持按时间筛选。

## 目标

- 左侧「视图」区新增「已完成任务」入口。
- 「全部任务」只显示未完成的主线任务、支线任务、每日任务，不再显示已完成任务分区。
- 新增独立的已完成任务视图，展示所有已完成普通任务与已完成 occurrence。
- 已完成任务视图顶部提供时间筛选控件。
- 已完成任务视图使用独立筛选状态，不影响「全部任务」和「重复任务」视图的筛选状态。
- 点击已完成任务后，详情区仍能打开普通任务详情或 occurrence 详情。

## 非目标

- 不改变任务完成/取消完成的 Core 状态模型。
- 不新增新的 Core 数据结构或专用持久化字段。
- 不改变「已删除任务」视图、回收站策略或删除/恢复行为。
- 不改变现有 `QuestTimeFilter` 的筛选语义，包括「未来」选项。
- 不新增完成时间排序模式；本次仍沿用任务/occurrence 的 `displayDate` 按日期分组。

## UI 设计

### 左侧导航

在 `SidebarSelection` 中新增 `.completedTasks`，并在侧边栏「视图」区新增：

- 文案：`已完成任务`
- 图标：`checkmark.seal` 或 `checkmark.circle`

导航顺序建议为：全部任务、已完成任务、重复任务、已删除任务、动态时间线。这样当前任务与历史完成任务相邻，语义更清晰。

### 全部任务视图

「全部任务」继续使用现有全局 `selectedTimeFilter`。内容只保留：

- 主线任务
- 支线任务
- 每日任务

这些分区只接收未完成 item：`filteredItems.filter { !$0.isCompleted }`。`QuestListView` 不再接收或渲染 `completedGroups`。

### 已完成任务视图

新增 `CompletedTasksView`：

- 接收 `store`、`selectedItemID` 绑定，以及一个选中 item 回调或详情筛选上下文回调。
- 内部持有独立状态：`@State private var completedTimeFilter: QuestTimeFilter = .today`。
- 顶部显示标题「已完成任务」和 `TimeFilterPicker(selectedTimeFilter: $completedTimeFilter)`。
- 数据来源：`store.listItems(in: completedTimeFilter).filter { $0.isCompleted }`。
- 展示方式：按 `groupedByDisplayDate()` 日期分组，复用 `QuestSection(title: "已完成任务", ...)` 或等价的 List 结构。
- 空状态文案：`当前时间范围内暂无已完成任务`。

## 详情区联动

当前详情解析使用 `store.detailTarget(for: selectedItemID, in: selectedTimeFilter)`。引入独立已完成筛选后，需要确保点击已完成 occurrence 时使用 `completedTimeFilter` 解析，否则 occurrence 可能因为不在全局筛选范围内而解析失败。

推荐在 `ContentView` 增加独立状态记录详情解析使用的筛选上下文，例如：

- `@State private var detailTimeFilter: QuestTimeFilter = .today`
- 当普通/重复/目标视图选择 item 时，同步为对应视图的筛选器。
- 当已完成任务视图选择 item 时，同步为 `completedTimeFilter`。

详情区统一调用 `store.detailTarget(for: selectedItemID, in: detailTimeFilter)`。这样普通任务与 occurrence 的详情打开逻辑不需要拆分。

## 数据与 Core 设计

本次主要是 UI 架构调整，Core 层不新增持久化字段。继续复用：

- `QuestStore.listItems(in:)`
- `QuestListItem.isCompleted`
- `QuestListItem.groupedByDisplayDate()`
- `QuestStore.detailTarget(for:in:)`

完成状态仍由现有模型承载：普通任务使用 `Quest.isCompleted`，重复 occurrence 使用 `QuestOccurrenceState.isCompleted`。

## 测试计划

- CoreChecks 无需新增业务模型测试；完成状态和时间筛选已有覆盖。
- Build 验证 SwiftUI 编译通过。
- 代码审查验证：
  - 「全部任务」不再渲染已完成分区。
  - 左侧存在「已完成任务」入口。
  - `CompletedTasksView` 使用自己的 `completedTimeFilter`。
  - 已完成 occurrence 点击后使用对应筛选上下文打开详情。

## 验收标准

- 左侧栏出现「已完成任务」入口。
- 「全部任务」视图只显示未完成任务，不再显示「已完成任务」分区。
- 进入「已完成任务」视图后，可以使用顶部时间筛选器筛选已完成任务。
- 已完成任务视图的筛选不会改变「全部任务」或「重复任务」的筛选状态。
- 点击已完成普通任务或 occurrence 均能打开正确详情。
- `QuestListCoreChecks` 和 `swift build` 通过。
