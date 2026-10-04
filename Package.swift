// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure logic (Pomodoro timing, preference parsing). No system calls, so it can
        // be tested on its own.
        .target(
            name: "SwitchboardKit",
            path: "Sources/SwitchboardKit"
        ),
        .executableTarget(
            name: "Switchboard",
            dependencies: ["SwitchboardKit"],
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
