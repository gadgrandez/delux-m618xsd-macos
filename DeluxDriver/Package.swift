// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DeluxDriver",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DeluxKit", targets: ["DeluxKit"]),
        .executable(name: "deluxctl", targets: ["deluxctl"]),
        .executable(name: "DeluxDriverApp", targets: ["DeluxDriverApp"]),
    ],
    targets: [
        .target(
            name: "DeluxKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation"), .linkedFramework("CoreBluetooth")]
        ),
        .executableTarget(name: "deluxctl", dependencies: ["DeluxKit"]),
        .executableTarget(name: "DeluxDriverApp", dependencies: ["DeluxKit"]),
        .executableTarget(name: "selftest", dependencies: ["DeluxKit"]),
    ]
)
