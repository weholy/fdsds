// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Saver",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/pvieito/PythonKit.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "Saver",
            dependencies: ["PythonKit"]
        )
    ]
)
