// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KB96Control",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "KB96Control", targets: ["KB96Control"])],
    targets: [.executableTarget(
        name: "KB96Control",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ApplicationServices"),
            .linkedFramework("IOKit")
        ]
    ), .testTarget(name: "KB96ControlTests", dependencies: ["KB96Control"])]
)
