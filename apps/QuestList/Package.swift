// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuestList",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuestListCore", targets: ["QuestListCore"]),
        .executable(name: "QuestList", targets: ["QuestList"]),
        .executable(name: "QuestListCoreChecks", targets: ["QuestListCoreChecks"])
    ],
    targets: [
        .target(name: "QuestListCore"),
        .executableTarget(name: "QuestList", dependencies: ["QuestListCore"]),
        .executableTarget(name: "QuestListCoreChecks", dependencies: ["QuestListCore"])
    ]
)
