// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExamTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ExamCore"),
        .executableTarget(name: "ExamTracker", dependencies: ["ExamCore"]),
        .testTarget(name: "ExamCoreTests", dependencies: ["ExamCore"])
    ]
)
