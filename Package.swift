// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacClean",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacCleanCore", targets: ["MacCleanCore"]),
        .executable(name: "maccleanctl", targets: ["maccleanctl"]),
        .executable(name: "MacClean", targets: ["MacCleanApp"]),
    ],
    targets: [
        // 순수 Foundation 코어. UI 프레임워크에 의존하지 않으므로 단위 테스트가 쉽고,
        // 나중에 CLI / GUI / 위젯 어디에든 그대로 얹을 수 있다.
        .target(name: "MacCleanCore"),

        // 코어 로직 검증용 CLI. GUI 없이도 scan / plan / clean 전 과정을 돌려볼 수 있다.
        .executableTarget(name: "maccleanctl", dependencies: ["MacCleanCore"]),

        // SwiftUI 앱.
        .executableTarget(name: "MacCleanApp", dependencies: ["MacCleanCore"]),

        .testTarget(name: "MacCleanCoreTests", dependencies: ["MacCleanCore"]),
    ]
)
