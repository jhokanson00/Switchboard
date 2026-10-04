// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v15)],
    dependencies: [
        // In-app updates from GitHub Releases ("Check for Updates…").
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // Pure logic (Pomodoro timing, preference parsing). No system calls, so it can
        // be tested on its own.
        .target(
            name: "SwitchboardKit",
            path: "Sources/SwitchboardKit"
        ),
        .executableTarget(
            name: "Switchboard",
            dependencies: ["SwitchboardKit", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Switchboard",
            linkerSettings: [
                // Embed Info.plist in the binary so the Bluetooth and Automation usage
                // strings exist even when running the bare executable. Without them,
                // macOS kills the process the moment it touches Bluetooth.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Resources/Info.plist",
                    // Sparkle.framework is copied into Contents/Frameworks by build-app.sh.
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        ),
        .testTarget(
            name: "SwitchboardKitTests",
            dependencies: ["SwitchboardKit"],
            path: "Tests/SwitchboardKitTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
