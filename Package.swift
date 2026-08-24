// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChistkaLogov",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ChistkaLogov",
            path: "Sources/ChistkaLogov"
        )
    ]
)
