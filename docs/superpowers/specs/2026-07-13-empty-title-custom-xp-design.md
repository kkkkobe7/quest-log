# 新建任务空标题与任务级经验值自定义设计

## 背景

当前 QuestList 新建任务时会把标题初始化为“新建任务”，用户点击标题输入框后需要手动删除这四个字才能输入真实标题。当前任务经验值完全由 `QuestDifficulty.xpReward` 固定映射决定，用户不能为单个任务调整经验值。

## 目标

- 新建任务标题默认为空字符串，详情页通过占位文案引导输入。
- 所有列表展示位置对空标题使用“未命名任务”作为显示 fallback，避免空白行。
- 支持每个任务单独自定义 XP；难度继续作为标签、颜色和默认推荐值。
- 普通任务完成、重复任务 occurrence 完成都按任务/occurrence 当前 XP 发放。
- 兼容旧 JSON：缺少新 XP 字段时根据难度默认值回退。

## 设计

### 空标题规则

`QuestStore.addQuest(goalID:)` 创建新任务时传入空标题。`Quest` 解码旧数据缺少 `title` 时也默认空字符串。UI 层不把空字符串写回“新建任务”，而是在列表行、回收站行、occurrence 投影等展示处统一显示“未命名任务”。详情页标题输入框继续使用占位文案“输入任务标题”。

### 任务级 XP

在 `Quest` 上新增任务级 XP 字段，建议命名为 `xpReward` 或内部存储字段 `customXPReward`。新任务创建时 XP 初始值使用当前难度默认值（普通=25）。任务难度变更后不强制覆盖用户已经改过的 XP；难度只表示标签、颜色与推荐值。

普通任务完成时，`QuestStore.completeQuest(id:)` 发放任务自己的 XP。`QuestListItem` 也暴露当前展示项的 XP，用于列表 XP badge 和 occurrence 完成发放。

### occurrence XP 覆盖

`QuestOccurrenceOverride` 新增 XP 字段。occurrence 默认继承父任务 XP；在 occurrence 详情中应用“仅这一次”或“之后全部”时，XP 与标题、奖励、分区、难度、日期一样作为 override 的一部分保存。完成 occurrence 时发放该 occurrence 当前投影出的 XP。

### UI

任务详情页在“难度”下方新增“经验值”输入行，使用中文文案，限制为非负整数。occurrence 详情页同样增加“经验值”输入行，编辑后随“应用覆盖配置”一起保存。列表与徽章仍显示 `+N XP`。

### 验证

使用 `QuestListCoreChecks` 覆盖：

- 新建任务标题为空。
- 空标题列表展示 fallback 为“未命名任务”。
- 自定义 XP 的普通任务完成后按自定义值发放，且重复完成不重复发放。
- 旧 JSON 缺少 XP 字段时按难度默认 XP 回退。
- occurrence 继承父任务 XP，并支持“仅这一次/之后全部”覆盖。
- `swift run QuestListCoreChecks` 和 `swift build` 通过。

## 非目标

- 不做全局难度 XP 配置。
- 不做负数 XP、浮点 XP 或复杂奖励公式。
- 不改变现有等级计算规则。
