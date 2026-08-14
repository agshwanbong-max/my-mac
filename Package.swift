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
        //
        // 번역 파일도 여기 있다. 화면 문자열의 절반 이상(규칙 설명, 판정 이유)이
        // 코어에서 나오므로, 카탈로그를 앱과 코어로 나누면 같은 말을 두 번 번역하게 된다.
        .target(
            name: "MacCleanCore",
            resources: [.process("Resources")]
        ),

        // 코어 로직 검증용 CLI. GUI 없이도 scan / plan / clean 전 과정을 돌려볼 수 있다.
        .executableTarget(name: "maccleanctl", dependencies: ["MacCleanCore"]),

        // SwiftUI 앱.
        .executableTarget(name: "MacCleanApp", dependencies: ["MacCleanCore"]),

        .testTarget(name: "MacCleanCoreTests", dependencies: ["MacCleanCore"]),
    ]
)
