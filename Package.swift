// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GanttLab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GanttLab", targets: ["GanttLab"])
    ],
    targets: [
        .executableTarget(
            name: "GanttLab",
            path: "Sources"
        )
    ]
)

