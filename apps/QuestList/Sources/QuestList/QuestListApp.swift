import SwiftUI
import AppKit
import QuestListCore

@main
struct QuestListApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("任务清单", id: "main") {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    activateQuestListWindow()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建任务清单窗口") {
                    openQuestListWindow()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        MenuBarExtra("任务清单", systemImage: "checkmark.circle") {
            Button("打开任务清单") {
                openQuestListWindow()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("退出 QuestList") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func openQuestListWindow() {
        openWindow(id: "main")
        activateQuestListWindow()
    }

    private func activateQuestListWindow() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

extension QuestDifficulty {
    var tint: Color {
        switch self {
        case .easy: .green
        case .medium: .blue
        case .hard: .orange
        case .epic: .purple
        }
    }
}

enum RecurrenceRuleKind: String, CaseIterable, Identifiable {
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly
    case fixedInterval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "每日"
        case .weekdays: "工作日"
        case .weekly: "每周自定义"
        case .monthly: "每月几号"
        case .yearly: "每年哪天"
        case .fixedInterval: "固定间隔"
        }
    }

    var defaultRule: QuestRecurrenceRule {
        switch self {
        case .daily: .daily
        case .weekdays: .weekdays
        case .weekly: .weekly(weekdays: [.monday])
        case .monthly: .monthly(day: 1)
        case .yearly: .yearly(month: 1, day: 1)
        case .fixedInterval: .fixedInterval(value: 1, unit: .day)
        }
    }
}

extension QuestRecurrenceRule {
    var kind: RecurrenceRuleKind {
        switch self {
        case .daily: .daily
        case .weekdays: .weekdays
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        case .fixedInterval: .fixedInterval
        }
    }
}

extension QuestWeekday: Identifiable {
    public var id: Int { rawValue }

    var title: String {
        switch self {
        case .sunday: "周日"
        case .monday: "周一"
        case .tuesday: "周二"
        case .wednesday: "周三"
        case .thursday: "周四"
        case .friday: "周五"
        case .saturday: "周六"
        }
    }
}

extension RecurrenceIntervalUnit: Identifiable {
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "天"
        case .week: "周"
        }
    }
}

enum SidebarSelection: Hashable {
    case allQuests
    case recurringTasks
    case trash
    case timeline
    case goal(UUID)
}

struct ContentView: View {
    @StateObject private var store = QuestStore()
    @State private var selection: SidebarSelection? = .allQuests
    @State private var selectedItemID: String?
    @State private var newGoalName = ""
    @State private var selectedTimeFilter: QuestTimeFilter = .today

    private var baseQuests: [Quest] {
        switch selection {
        case .goal(let goalID):
            store.quests.filter { $0.goalID == goalID }
        case .allQuests, .recurringTasks, .trash, .timeline, .none:
            store.quests
        }
    }

    private var filteredItems: [QuestListItem] {
        let items = store.listItems(in: selectedTimeFilter)
        switch selection {
        case .goal(let goalID):
            return items.filter { $0.goalID == goalID }
        default:
            return items
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if selection == .timeline {
                ActivityTimelineView(store: store)
                    .navigationTitle("动态时间线")
            } else if selection == .recurringTasks {
                RecurringTasksView(
                    store: store,
                    selectedTimeFilter: $selectedTimeFilter,
                    selectedItemID: $selectedItemID
                )
                .navigationTitle("重复任务")
            } else if selection == .trash {
                TrashView(store: store)
                    .navigationTitle("已删除任务")
            } else {
                let activeItems = filteredItems.filter { !$0.isCompleted }
                let mainGroups = activeItems.filter { $0.category == .main }.groupedByDisplayDate()
                let sideGroups = activeItems.filter { $0.category == .side }.groupedByDisplayDate()
                let dailyGroups = activeItems.filter { $0.category == .daily }.groupedByDisplayDate()
                let completedGroups = filteredItems.filter { $0.isCompleted }.groupedByDisplayDate()

                QuestListView(
                    store: store,
                    mainGroups: mainGroups,
                    sideGroups: sideGroups,
                    dailyGroups: dailyGroups,
                    completedGroups: completedGroups,
                    selectedTimeFilter: $selectedTimeFilter,
                    selectedItemID: $selectedItemID,
                    onAddQuest: addQuest
                )
                .navigationTitle(listTitle)
            }
        } detail: {
            if let selectedItemID, let target = store.detailTarget(for: selectedItemID, in: selectedTimeFilter) {
                switch target {
                case .quest(let questID):
                    QuestDetailView(store: store, questID: questID)
                case .occurrence(let item):
                    if let occurrenceDate = item.occurrenceDate {
                        OccurrenceDetailView(store: store, item: item, occurrenceDate: occurrenceDate)
                    } else {
                        EmptyQuestView()
                    }
                }
            } else {
                EmptyQuestView()
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                PlayerCard(profile: store.profile)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section("视图") {
                Label("全部任务", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSelection.allQuests)
                Label("重复任务", systemImage: "repeat")
                    .tag(SidebarSelection.recurringTasks)
                Label("已删除任务", systemImage: "trash")
                    .tag(SidebarSelection.trash)
                Label("动态时间线", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarSelection.timeline)
            }

            Section("目标") {
                ForEach(store.goals) { goal in
                    Label(goal.name, systemImage: "target")
                        .tag(SidebarSelection.goal(goal.id))
                }

                HStack {
                    TextField("新建目标", text: $newGoalName)
                    Button {
                        store.addGoal(name: newGoalName)
                        newGoalName = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(newGoalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("任务清单")
    }

    private var listTitle: String {
        switch selection {
        case .goal(let goalID):
            store.goal(id: goalID)?.name ?? "目标"
        case .recurringTasks:
            "重复任务"
        case .trash:
            "已删除任务"
        default:
            "全部任务"
        }
    }

    private func addQuest() {
        let goalID: UUID?
        if case .goal(let selectedGoalID) = selection {
            goalID = selectedGoalID
        } else {
            goalID = nil
        }
        selectedItemID = store.addQuest(goalID: goalID).uuidString
    }
}

struct PlayerCard: View {
    let profile: PlayerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("等级 \(profile.level)")
                    .font(.headline)
            }
            ProgressView(value: profile.progressToNextLevel)
            Text("\(profile.totalXP) 经验值")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TimeFilterPicker: View {
    @Binding var selectedTimeFilter: QuestTimeFilter

    var body: some View {
        Picker("时间筛选", selection: $selectedTimeFilter) {
            ForEach(QuestTimeFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct QuestListView: View {
    @ObservedObject var store: QuestStore
    let mainGroups: [QuestItemDateGroup]
    let sideGroups: [QuestItemDateGroup]
    let dailyGroups: [QuestItemDateGroup]
    let completedGroups: [QuestItemDateGroup]
    @Binding var selectedTimeFilter: QuestTimeFilter
    @Binding var selectedItemID: String?
    let onAddQuest: () -> Void

    private var isEmpty: Bool {
        mainGroups.isEmpty && sideGroups.isEmpty && dailyGroups.isEmpty && completedGroups.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("任务")
                        .font(.headline)
                    Spacer()
                    Button(action: onAddQuest) {
                        Label("新建任务", systemImage: "plus")
                    }
                }

                TimeFilterPicker(selectedTimeFilter: $selectedTimeFilter)
            }
            .padding()

            if isEmpty {
                ContentUnavailableView(
                    "暂无任务",
                    systemImage: "flag.checkered",
                    description: Text("当前时间范围内暂无任务，换个筛选范围或创建新任务吧")
                )
            } else {
                List(selection: $selectedItemID) {
                    QuestSection(title: "主线任务", dateGroups: mainGroups, store: store)
                    QuestSection(title: "支线任务", dateGroups: sideGroups, store: store)
                    QuestSection(title: "每日任务", dateGroups: dailyGroups, store: store)
                    QuestSection(title: "已完成任务", dateGroups: completedGroups, store: store, isExpandedByDefault: false)
                }
            }
        }
    }
}

struct QuestSection: View {
    let title: String
    let dateGroups: [QuestItemDateGroup]
    @ObservedObject var store: QuestStore
    @State private var isExpanded: Bool

    init(title: String, dateGroups: [QuestItemDateGroup], store: QuestStore, isExpandedByDefault: Bool = true) {
        self.title = title
        self.dateGroups = dateGroups
        self.store = store
        self._isExpanded = State(initialValue: isExpandedByDefault)
    }

    var body: some View {
        Section(isExpanded: $isExpanded) {
            if dateGroups.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dateGroups) { group in
                    Text(dateTitle(for: group.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ForEach(group.items) { item in
                        QuestRow(store: store, item: item)
                            .tag(item.id)
                    }
                }
            }
        } header: {
            Text(title)
        }
    }

    private func dateTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if calendar.isDateInTomorrow(date) {
            return "明天"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct QuestRow: View {
    @ObservedObject var store: QuestStore
    let item: QuestListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    if item.isOccurrence, let occurrenceDate = item.occurrenceDate {
                        store.updateOccurrenceCompletion(parentQuestID: item.questID, date: occurrenceDate, isCompleted: !item.isCompleted)
                    } else if item.isCompleted {
                        store.updateQuest(id: item.questID) { quest in
                            quest.isCompleted = false
                        }
                    } else {
                        store.completeQuest(id: item.questID)
                    }
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名任务" : item.title)
                    .font(.headline)
                    .foregroundStyle(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                    .strikethrough(item.isCompleted)
                if item.isOccurrence {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DifficultyBadge(difficulty: item.difficulty)
                XPBadge(xp: item.xpReward)
            }
            HStack(spacing: 10) {
                if let goalName = store.goal(id: item.goalID)?.name {
                    Label(goalName, systemImage: "target")
                }
                Label(item.displayDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label(item.category.rawValue, systemImage: item.category.systemImage)
                if !item.reward.isEmpty {
                    Label(item.reward, systemImage: "gift")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(role: .destructive) {
                store.deleteQuest(id: item.questID)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

struct RecurringTasksView: View {
    @ObservedObject var store: QuestStore
    @Binding var selectedTimeFilter: QuestTimeFilter
    @Binding var selectedItemID: String?

    private var recurringParents: [Quest] {
        store.quests.filter { $0.recurrenceRule != nil }.sorted { $0.title < $1.title }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("重复任务")
                    .font(.headline)
                TimeFilterPicker(selectedTimeFilter: $selectedTimeFilter)
            }
            .padding()

            if recurringParents.isEmpty {
                ContentUnavailableView(
                    "暂无重复任务",
                    systemImage: "repeat",
                    description: Text("在任务详情中开启重复任务后，会在这里按父任务分组展示")
                )
            } else {
                List(selection: $selectedItemID) {
                    ForEach(recurringParents) { parent in
                        let items = store.listItems(in: selectedTimeFilter)
                            .filter { $0.questID == parent.id && $0.isOccurrence }
                        Section(parent.displayTitle) {
                            if items.isEmpty {
                                Text("当前时间范围内暂无 occurrence")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(items) { item in
                                    QuestRow(store: store, item: item)
                                        .tag(item.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TrashView: View {
    @ObservedObject var store: QuestStore

    private var deletedQuests: [Quest] {
        store.deletedQuests()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("已删除任务")
                    .font(.headline)
                Text("删除后保留 30 天，可随时恢复")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            if deletedQuests.isEmpty {
                ContentUnavailableView(
                    "回收站为空",
                    systemImage: "trash",
                    description: Text("删除的任务会出现在这里，可以随时恢复")
                )
            } else {
                List(deletedQuests) { quest in
                    TrashRow(store: store, quest: quest)
                }
            }
        }
    }
}

struct TrashRow: View {
    @ObservedObject var store: QuestStore
    let quest: Quest

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(quest.displayTitle)
                    .font(.headline)
                    .foregroundStyle(quest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                HStack(spacing: 10) {
                    Label(quest.category.rawValue, systemImage: quest.category.systemImage)
                    if let deletedAt = quest.deletedAt {
                        Label(deletedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "trash")
                    }
                    if quest.recurrenceRule != nil {
                        Label("重复任务", systemImage: "repeat")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.restoreQuest(id: quest.id)
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

struct QuestDetailView: View {
    @ObservedObject var store: QuestStore
    let questID: UUID
    @State private var draftTitle = ""
    @State private var draftReward = ""
    @State private var draftXPReward = ""
    @State private var draftLog = ""
    @State private var showsDeleteConfirmation = false

    private var currentQuest: Quest? {
        store.quest(id: questID)
    }

    var body: some View {
        if let currentQuest {
            questForm(for: currentQuest)
        } else {
            EmptyQuestView()
        }
    }

    private func questForm(for currentQuest: Quest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Form {
                    Section("任务") {
                        EditableTextRow(title: "标题", placeholder: "输入任务标题", text: $draftTitle)
                            .onChange(of: draftTitle) { _, newValue in
                                store.updateQuest(id: questID) { quest in
                                    quest.title = newValue
                                }
                            }
                        Toggle("已完成", isOn: completionBinding)
                        Picker("任务分区", selection: questBinding(\.category, fallback: currentQuest.category)) {
                            ForEach(QuestCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.systemImage)
                                    .tag(category)
                            }
                        }
                        Picker("难度", selection: questBinding(\.difficulty, fallback: currentQuest.difficulty)) {
                            ForEach(QuestDifficulty.allCases) { difficulty in
                                Text("\(difficulty.rawValue) · \(difficulty.xpReward) 经验")
                                    .tag(difficulty)
                            }
                        }
                        EditableTextRow(title: "经验值", placeholder: "输入经验值（非负整数）", text: $draftXPReward)
                            .onChange(of: draftXPReward) { _, newValue in
                                let sanitizedValue = sanitizedXPText(newValue)
                                if sanitizedValue != newValue {
                                    draftXPReward = sanitizedValue
                                    return
                                }
                                if let xp = Int(sanitizedValue) {
                                    store.updateQuest(id: questID) { quest in
                                        quest.baseXPReward = xp
                                    }
                                }
                            }
                        EditableTextRow(title: "奖励", placeholder: "一杯咖啡、散步、打一局游戏…", text: $draftReward)
                            .onChange(of: draftReward) { _, newValue in
                                store.updateQuest(id: questID) { quest in
                                    quest.reward = newValue
                                }
                            }
                    }

                    Section("时间") {
                        DatePicker("开始", selection: startDateBinding)
                        Toggle("设置截止时间 / 重复结束时间", isOn: dueDateToggleBinding)
                        if currentQuest.dueDate != nil {
                            DatePicker(currentQuest.recurrenceRule == nil ? "截止" : "重复结束", selection: dueDateBinding)
                        }
                    }

                    Section("重复任务") {
                        Toggle("开启重复任务", isOn: recurrenceEnabledBinding)
                        if let recurrenceRule = currentQuest.recurrenceRule {
                            Picker("重复模式", selection: recurrenceKindBinding) {
                                ForEach(RecurrenceRuleKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            recurrenceRuleConfiguration(for: recurrenceRule)
                        }
                    }

                    Section("所属目标") {
                        Picker("目标", selection: questBinding(\.goalID, fallback: currentQuest.goalID)) {
                            Text("无目标").tag(Optional<UUID>.none)
                            ForEach(store.goals) { goal in
                                Text(goal.name).tag(Optional(goal.id))
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(minHeight: 330)

                ProgressLogPanel(
                    logs: store.logs(for: currentQuest.id),
                    draftLog: $draftLog,
                    onAdd: {
                        store.addLog(questID: currentQuest.id, content: draftLog)
                        draftLog = ""
                    }
                )

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("删除任务", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .navigationTitle("任务详情")
        .confirmationDialog("删除后任务将进入“已删除任务”，30 天内可恢复，确定删除吗？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                store.deleteQuest(id: questID)
            }
            Button("取消", role: .cancel) {}
        }
        .task(id: questID) {
            if let refreshedQuest = store.quest(id: questID) {
                syncDraftFields(from: refreshedQuest)
            }
        }
    }

    private func syncDraftFields(from quest: Quest) {
        draftTitle = quest.title
        draftReward = quest.reward
        draftXPReward = String(quest.baseXPReward)
    }

    private func questBinding<Value>(_ keyPath: WritableKeyPath<Quest, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { store.quest(id: questID)?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    quest[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var completionBinding: Binding<Bool> {
        Binding(
            get: { store.quest(id: questID)?.isCompleted ?? false },
            set: { newValue in
                if newValue {
                    store.completeQuest(id: questID)
                } else {
                    store.updateQuest(id: questID) { quest in
                        quest.isCompleted = false
                    }
                }
            }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { store.quest(id: questID)?.startDate ?? .now },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    quest.startDate = newValue
                }
            }
        )
    }

    private var dueDateToggleBinding: Binding<Bool> {
        Binding(
            get: { store.quest(id: questID)?.dueDate != nil },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    quest.dueDate = newValue ? (quest.dueDate ?? .now) : nil
                }
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { store.quest(id: questID)?.dueDate ?? .now },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    quest.dueDate = newValue
                }
            }
        )
    }

    private var recurrenceEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.quest(id: questID)?.recurrenceRule != nil },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    quest.recurrenceRule = newValue ? (quest.recurrenceRule ?? .daily) : nil
                }
            }
        )
    }

    private var recurrenceKindBinding: Binding<RecurrenceRuleKind> {
        Binding(
            get: { store.quest(id: questID)?.recurrenceRule?.kind ?? .daily },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    quest.recurrenceRule = newValue.defaultRule
                }
            }
        )
    }

    @ViewBuilder
    private func recurrenceRuleConfiguration(for recurrenceRule: QuestRecurrenceRule) -> some View {
        switch recurrenceRule {
        case .daily:
            Text("每天生成一个任务实例")
                .foregroundStyle(.secondary)
        case .weekdays:
            Text("每周一到周五生成任务实例")
                .foregroundStyle(.secondary)
        case .weekly:
            ForEach(QuestWeekday.allCases) { weekday in
                Toggle(weekday.title, isOn: weeklyWeekdayBinding(weekday))
            }
        case .monthly:
            Stepper("每月第 \(monthlyDayBinding.wrappedValue) 天", value: monthlyDayBinding, in: 1...31)
        case .yearly:
            Picker("月份", selection: yearlyMonthBinding) {
                ForEach(1...12, id: \.self) { month in
                    Text("\(month) 月").tag(month)
                }
            }
            Stepper("日期：\(yearlyDayBinding.wrappedValue) 日", value: yearlyDayBinding, in: 1...31)
        case .fixedInterval:
            Stepper("间隔：\(intervalValueBinding.wrappedValue)", value: intervalValueBinding, in: 1...365)
            Picker("单位", selection: intervalUnitBinding) {
                ForEach([RecurrenceIntervalUnit.day, .week]) { unit in
                    Text(unit.title).tag(unit)
                }
            }
        }
    }

    private func weeklyWeekdayBinding(_ weekday: QuestWeekday) -> Binding<Bool> {
        Binding(
            get: {
                guard case .weekly(let weekdays) = store.quest(id: questID)?.recurrenceRule else { return false }
                return weekdays.contains(weekday)
            },
            set: { isEnabled in
                store.updateQuest(id: questID) { quest in
                    guard case .weekly(var weekdays) = quest.recurrenceRule else { return }
                    if isEnabled {
                        weekdays.insert(weekday)
                    } else {
                        weekdays.remove(weekday)
                    }
                    quest.recurrenceRule = .weekly(weekdays: weekdays.isEmpty ? [.monday] : weekdays)
                }
            }
        )
    }

    private var monthlyDayBinding: Binding<Int> {
        Binding(
            get: {
                guard case .monthly(let day) = store.quest(id: questID)?.recurrenceRule else { return 1 }
                return day
            },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    quest.recurrenceRule = .monthly(day: newValue)
                }
            }
        )
    }

    private var yearlyMonthBinding: Binding<Int> {
        Binding(
            get: {
                guard case .yearly(let month, _) = store.quest(id: questID)?.recurrenceRule else { return 1 }
                return month
            },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    guard case .yearly(_, let day) = quest.recurrenceRule else { return }
                    quest.recurrenceRule = .yearly(month: newValue, day: day)
                }
            }
        )
    }

    private var yearlyDayBinding: Binding<Int> {
        Binding(
            get: {
                guard case .yearly(_, let day) = store.quest(id: questID)?.recurrenceRule else { return 1 }
                return day
            },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    guard case .yearly(let month, _) = quest.recurrenceRule else { return }
                    quest.recurrenceRule = .yearly(month: month, day: newValue)
                }
            }
        )
    }

    private var intervalValueBinding: Binding<Int> {
        Binding(
            get: {
                guard case .fixedInterval(let value, _) = store.quest(id: questID)?.recurrenceRule else { return 1 }
                return value
            },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    guard case .fixedInterval(_, let unit) = quest.recurrenceRule else { return }
                    quest.recurrenceRule = .fixedInterval(value: newValue, unit: unit)
                }
            }
        )
    }

    private var intervalUnitBinding: Binding<RecurrenceIntervalUnit> {
        Binding(
            get: {
                guard case .fixedInterval(_, let unit) = store.quest(id: questID)?.recurrenceRule else { return .day }
                return unit
            },
            set: { newValue in
                store.updateQuest(id: questID) { quest in
                    guard case .fixedInterval(let value, _) = quest.recurrenceRule else { return }
                    quest.recurrenceRule = .fixedInterval(value: value, unit: newValue)
                }
            }
        )
    }
}

struct OccurrenceDetailView: View {
    @ObservedObject var store: QuestStore
    let item: QuestListItem
    let occurrenceDate: Date
    @State private var draftTitle = ""
    @State private var draftReward = ""
    @State private var draftLog = ""
    @State private var draftCategory: QuestCategory = .side
    @State private var draftDifficulty: QuestDifficulty = .medium
    @State private var draftXPReward = ""
    @State private var draftDueDate = Date()
    @State private var asksForScope = false

    private var occurrenceID: String {
        QuestOccurrence(parentQuestID: item.questID, date: occurrenceDate).id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Form {
                    Section("重复任务 occurrence") {
                        Toggle("已完成", isOn: completionBinding)
                        EditableTextRow(title: "标题", placeholder: "输入任务标题", text: $draftTitle)
                        Picker("任务分区", selection: $draftCategory) {
                            ForEach(QuestCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.systemImage).tag(category)
                            }
                        }
                        Picker("难度", selection: $draftDifficulty) {
                            ForEach(QuestDifficulty.allCases) { difficulty in
                                Text("\(difficulty.rawValue) · \(difficulty.xpReward) 经验").tag(difficulty)
                            }
                        }
                        EditableTextRow(title: "经验值", placeholder: "输入经验值（非负整数）", text: $draftXPReward)
                            .onChange(of: draftXPReward) { _, newValue in
                                let sanitizedValue = sanitizedXPText(newValue)
                                if sanitizedValue != newValue {
                                    draftXPReward = sanitizedValue
                                }
                            }
                        EditableTextRow(title: "奖励", placeholder: "一杯咖啡、散步、打一局游戏…", text: $draftReward)
                        DatePicker("日期 / 截止", selection: $draftDueDate)
                        Button("应用覆盖配置") {
                            asksForScope = true
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(minHeight: 260)

                ProgressLogPanel(
                    logs: store.logs(forOccurrenceID: occurrenceID),
                    draftLog: $draftLog,
                    onAdd: {
                        store.addOccurrenceLog(parentQuestID: item.questID, date: occurrenceDate, content: draftLog)
                        draftLog = ""
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .navigationTitle("重复任务详情")
        .task(id: item.id) {
            syncDraftFields()
        }
        .confirmationDialog("选择影响范围", isPresented: $asksForScope, titleVisibility: .visible) {
            Button(OccurrenceEditScope.once.title) {
                applyOverride(scope: .once)
            }
            Button(OccurrenceEditScope.future.title) {
                applyOverride(scope: .future)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅这一次只修改当前 occurrence；之后全部会影响当前日期之后的 occurrence。")
        }
    }

    private var completionBinding: Binding<Bool> {
        Binding(
            get: { store.listItems(in: .all).first(where: { $0.id == item.id })?.isCompleted ?? item.isCompleted },
            set: { newValue in
                store.updateOccurrenceCompletion(parentQuestID: item.questID, date: occurrenceDate, isCompleted: newValue)
            }
        )
    }

    private func syncDraftFields() {
        draftTitle = item.title
        draftReward = item.reward
        draftCategory = item.category
        draftDifficulty = item.difficulty
        draftXPReward = String(item.xpReward)
        draftDueDate = item.displayDate
    }

    private func applyOverride(scope: OccurrenceEditScope) {
        store.applyOccurrenceOverride(
            parentQuestID: item.questID,
            date: occurrenceDate,
            scope: scope,
            override: QuestOccurrenceOverride(
                title: draftTitle,
                reward: draftReward,
                category: draftCategory,
                difficulty: draftDifficulty,
                dueDate: draftDueDate,
                xpReward: Int(sanitizedXPText(draftXPReward))
            )
        )
    }
}

func sanitizedXPText(_ text: String) -> String {
    String(text.filter(\.isNumber))
}

struct EditableTextRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 24)
            TextField(placeholder, text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct ProgressLogPanel: View {
    let logs: [ProgressLog]
    @Binding var draftLog: String
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("过程记录")
                .font(.headline)

            ProgressLogComposer(text: $draftLog, onAdd: onAdd)

            ForEach(logs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.content)
                    Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if log.id != logs.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ProgressLogComposer: View {
    @Binding var text: String
    let onAdd: () -> Void

    private var canAdd: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("记录一下做了什么…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))

            Button("添加记录") {
                onAdd()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdd)
        }
    }
}

struct ActivityTimelineView: View {
    @ObservedObject var store: QuestStore

    var body: some View {
        if store.logs.isEmpty {
            ContentUnavailableView(
                "暂无记录",
                systemImage: "clock",
                description: Text("添加过程记录后将在这里显示")
            )
        } else {
            List(store.logs.sorted { $0.timestamp > $1.timestamp }) { log in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(store.questTitle(for: log.questID))
                            .font(.headline)
                        Spacer()
                        Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(log.content)
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct EmptyQuestView: View {
    var body: some View {
        ContentUnavailableView(
            "请选择一个任务",
            systemImage: "scroll",
            description: Text("选择一个任务，或新建任务以查看详情、记录、奖励和经验值")
        )
        .navigationTitle("任务详情")
    }
}

struct DifficultyBadge: View {
    let difficulty: QuestDifficulty

    var body: some View {
        Text(difficulty.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(difficulty.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(difficulty.tint)
    }
}

struct XPBadge: View {
    let xp: Int

    var body: some View {
        Text("+\(xp) XP")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.yellow.opacity(0.16), in: Capsule())
            .foregroundStyle(.orange)
    }
}
