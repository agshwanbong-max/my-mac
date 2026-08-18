// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacClean",
    // 번역의 원본 언어. `.lproj` 리소스가 있으면 SPM 이 이걸 요구한다 —
    // 사용자의 언어에 번역이 없을 때 어디로 되돌아갈지를 알아야 하기 때문이다.
    defaultLocalization: "ko",
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
        .executableTarget(
            name: "MacCleanApp",
            dependencies: ["MacCleanCore"],
            // 아이콘은 `build_app.sh` 가 소스 경로에서 직접 번들로 복사한다.
            // SPM 리소스로 넘기면 `MacClean_MacCleanApp.bundle` 안에 들어가는데,
            // `CFBundleIconFile` 은 Contents/Resources 바로 아래를 본다.
            exclude: ["Resources"]
        ),

        .testTarget(name: "MacCleanCoreTests", dependencies: ["MacCleanCore"]),
    ]
)
