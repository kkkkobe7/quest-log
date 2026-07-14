# 时间筛选「未来」选项设计

## 背景

QuestList 当前全局时间筛选支持「当日 / 近三天 / 近一周 / 近一个月 / 所有」，并在「全部任务」与「重复任务」视图共享同一筛选状态。现需新增「未来」选项，用于查看从明天开始的后续任务，同时避免重复任务在未来范围内展开出大量 occurrence。

## 目标

- 时间筛选器新增「未来」选项。
- 「未来」语义为：从明天 0 点开始的所有任务。
- 普通任务按现有 `displayDate` 规则过滤：有截止时间按截止时间，无截止时间按开始时间。
- 重复任务在「未来」下每个父任务只显示下一次命中的 occurrence，不额外展开多天。
- 「全部任务」与「重复任务」视图使用一致的 Core 查询结果。

## 非目标

- 不改变现有「当日 / 近三天 / 近一周 / 近一个月 / 所有」语义。
- 不新增自定义日期范围选择器。
- 不改变任务完成、XP 发放、occurrence 覆盖、过程记录等既有规则。
- 不在 UI 层单独裁剪 occurrence，避免不同视图规则不一致。

## Core 设计

### QuestTimeFilter

在 `QuestTimeFilter` 中新增 `.future`：

- `title` 返回「未来」。
- 新增或内聚一个 `futureStart(now:calendar:)` 计算：返回明天 0 点。
- `contains(_:now:calendar:)` 对 `.future` 走专门分支：`date >= futureStart(now:calendar:)`。
- `dateInterval(now:calendar:)` 继续只表达有限范围；`.all` 与 `.future` 都可返回 `nil`，避免用有限 `DateInterval` 错误表达开放式未来。

### 普通任务过滤

`QuestStore.listItems(in:)` 对普通任务继续调用 `timeFilter.contains(quest.displayDate, now:calendar:)`。`.future` 下不包含今天任务，只包含明天及之后的任务。

### 重复任务生成

`Quest.generateOccurrences(in:now:calendar:)` 对 `.future` 使用特殊规则：

- 从明天 0 点开始查找。
- 按天向后查找下一次匹配 recurrenceRule 的日期。
- 找到第一条 matching occurrence 后立即返回单元素数组。
- 若父任务存在 `dueDate`，查找不得超过重复任务结束日期。
- 若父任务没有 `dueDate`，查找上限设为从明天起最多 1 年再加 1 天，确保 yearly 规则也能找到下一次命中，同时避免无限循环。
- 若没有找到匹配日期，返回空数组。

## UI 设计

- `TimeFilterPicker` 继续使用 `QuestTimeFilter.allCases`，新增 `.future` 后自动出现「未来」。
- 「全部任务」视图不增加 UI 分支，仍按任务类型和日期分组展示。
- 「重复任务」视图不额外做去重逻辑，仍使用 `store.listItems(in: selectedTimeFilter)`；Core 保证 `.future` 下每个父任务最多一条 occurrence。
- 未来 occurrence 按其实际日期显示在对应日期组下，例如下一次是下周三，则显示在下周三分组。

## 测试计划

- CoreChecks 验证 `QuestTimeFilter.future.title == "未来"`。
- 验证 `.future` 排除今天任务，包含明天及之后的普通任务。
- 验证每日重复任务在 `.future` 下只返回明天一条 occurrence。
- 验证每周重复任务在 `.future` 下只返回下一次命中的日期，而不是展开多条。
- 验证 `QuestStore.listItems(in: .future)` 对重复任务每个父任务最多返回一条 occurrence。
- 回归运行 `QuestListCoreChecks` 与 `swift build`。

## 验收标准

- 时间筛选控件显示「未来」。
- 选择「未来」后，今天的普通任务不显示，明天及之后的普通任务显示。
- 选择「未来」后，每个重复任务只显示下一次未来 occurrence。
- 「全部任务」与「重复任务」两个视图对「未来」筛选结果一致。
- 既有时间筛选、重复任务编辑、完成状态、XP 与回收站功能不回归。
