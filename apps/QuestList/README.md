# QuestList

QuestList is a native macOS SwiftUI task list app with lightweight game-like progression.

## Run locally

```bash
cd apps/QuestList
swift run
```

## Build locally

```bash
cd apps/QuestList
swift build
```

## Features

- Three-column macOS layout: goals, quests, details.
- Goals for grouping quests.
- Quest fields: title, due date, goal, difficulty, reward, completion state.
- Difficulty-based XP rewards: Easy 10, Medium 25, Hard 50, Epic 100.
- Player level and XP progress display.
- Task-level progress logs.
- Global Activity Timeline across all quests.
- JSON file persistence under the user's Application Support directory.

## Notes

The original spec selected SwiftData, but the current machine only has Command Line Tools active and cannot load the SwiftData macro plugin via SwiftPM. This implementation uses local JSON persistence so the app can be built and run immediately with `swift build` / `swift run`. If full Xcode is installed later, the persistence layer can be migrated to SwiftData.

## Manual smoke test

1. Launch the app with `swift run`.
2. Create a new goal from the sidebar.
3. Create a new quest.
4. Edit title, due date, difficulty, goal, and reward.
5. Add a progress log.
6. Open Activity Timeline and verify the log appears.
7. Mark the quest completed and verify XP/level progress updates.
