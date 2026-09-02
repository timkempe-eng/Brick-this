// swift-tools-version: 5.9
import PackageDescription

/// This package exists purely to test `Dad/Shared/Core` — the parts of the app
/// that are Foundation-only and therefore compile and run anywhere, including
/// CI on Linux.
///
/// The same source directory is compiled into the app and all three extensions
/// by `project.yml`; this is a second way in, not a copy. Everything that
/// touches FamilyControls, ManagedSettings, DeviceActivity, CoreNFC or SwiftUI
/// is deliberately outside it and can only be built by Xcode.
///
///     swift test
let package = Package(
    name: "DadCore",
    products: [
        .library(name: "DadCore", targets: ["DadCore"]),
    ],
    targets: [
        .target(name: "DadCore", path: "Dad/Shared/Core"),
        .testTarget(name: "DadCoreTests", dependencies: ["DadCore"], path: "Tests/DadCoreTests"),
    ]
)
