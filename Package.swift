// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeekSheet",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WeekSheet"),
        .executableTarget(name: "WeekSheetApp", dependencies: ["WeekSheet"]),
        .testTarget(name: "WeekSheetTests", dependencies: ["WeekSheet"]),
    ]
)
