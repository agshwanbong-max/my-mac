import Foundation

/// 이 앱이 아는 모든 정리 규칙.
///
/// **여기 없는 경로는 절대 후보가 되지 않는다.** (허용 목록 방식)
/// "오래된 파일을 찾아서 지운다" 같은 휴리스틱은 이 앱에 없다.
public enum RuleCatalog {

    /// 캐시 폴더인 척하면서 실제로는 잃으면 곤란한 데이터를 담는 것으로 알려진 디렉터리들.
    /// `~/Library/Caches` 를 훑을 때 이 이름들은 건너뛴다.
    static let dataBearingCacheDirectories: Set<String> = [
        "com.spotify.client",          // 오프라인 저장 음악
        "com.apple.Music",             // 다운로드 받은 곡 캐시
        "com.apple.amp.mediasharingd",
        "CloudKit",                    // 동기화 상태 — 지우면 전량 재동기화
        "com.apple.cloudkit",
        "com.apple.bird",              // iCloud 데몬
        "com.apple.iCloudHelper",
        "FamilyCircle",
        "com.apple.Safari.SafeBrowsing",
        "com.docker.docker",           // 도커 상태 일부
        "com.apple.nsurlsessiond",     // 진행 중인 백그라운드 다운로드
        "com.apple.appstore",          // 다운로드 중인 앱
        "com.apple.commerce",
    ]

    /// 지워도 되지만 **다시 만드는 비용이 큰** 캐시들. 위험 등급을 `.review` 로 낮춰
    /// 기본 선택에서 빼고, 사용자가 알고 고르게 한다.
    ///
    /// 접두사로 비교하므로 `Adobe Camera Raw 2` 같은 버전 붙은 이름도 잡힌다.
    /// 실제 검사에서 `Adobe Camera Raw 2` 가 정확히-일치 차단을 빠져나가
    /// '안전' 등급으로 기본 선택됐던 적이 있다.
    static let costlyCacheDirectories: Set<String> = [
        "Adobe",                       // Camera Raw 미리보기 등 — 재생성이 매우 느리다
        "com.adobe.lightroom",         // 라이트룸 미리보기
        "SiriTTS",                     // Siri 음성 데이터 — 수백 MB 재다운로드
        "com.apple.siri",
        "ms-playwright",               // 자동화용 브라우저 빌드 — 수백 MB 재다운로드
        // 주의: 전용 규칙이 이미 있는 항목(Homebrew, Yarn, Xcode 등)은 여기 넣지 않는다.
        // 전용 규칙은 .safe 인데 일반 규칙이 .review 를 내면, 중복 정리가 더 조심스러운 쪽을
        // 남기면서 전용 규칙의 판단이 조용히 뒤집힌다.
    ]

    public static func all(paths: UserPaths) -> [CleanupRule] {
        var rules: [CleanupRule] = []

        // ─────────────────────────────────────────────────────────────
        // 휴지통
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "trash.user",
            category: .trash,
            risk: .review,
            path: ".Trash",
            mode: .eachChild,
            removal: .permanentDelete,
            minimumAgeDays: 0,
            minimumBytes: 0
        ))

        // ─────────────────────────────────────────────────────────────
        // Xcode — 256GB 맥에서 가장 크게 먹는 쪽
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "xcode.derivedData",
            category: .xcode,
            risk: .safe,
            path: "Library/Developer/Xcode/DerivedData",
            mode: .eachChild,
            minimumAgeDays: 0,
            minimumBytes: 10_000_000,
            ownerBundleIdentifier: "com.apple.dt.Xcode"
        ))

        rules.append(CleanupRule(
            id: "xcode.iosDeviceSupport",
            category: .xcode,
            risk: .review,
            path: "Library/Developer/Xcode/iOS DeviceSupport",
            mode: .eachChild,
            // 나이 조건을 아예 뺀다.
            // 처음엔 30일이었는데 실제 맥에서 17GB 가 전부 여기 걸려 한 줄도 안 나왔다. 7일로 낮춰도 마찬가지였다.
            // 애초에 이 폴더에 나이 기준이 안 맞는다. 중요한 건 "최근에 건드렸나" 가 아니라
            // "그 iOS 버전을 아직 쓰나" 인데, 그건 수정 시각으로 알 수 없다.
            // 폴더 이름이 곧 iOS 버전이라 사용자는 보면 안다. 확인 등급이라 직접 골라야 하고,
            // 휴지통으로 가므로 되돌릴 수도 있다. 판단은 사용자에게 넘긴다.
            minimumAgeDays: 0,
            minimumBytes: 10_000_000,
            ownerBundleIdentifier: "com.apple.dt.Xcode"
        ))

        rules.append(CleanupRule(
            id: "xcode.watchOSDeviceSupport",
            category: .xcode,
            risk: .review,
            path: "Library/Developer/Xcode/watchOS DeviceSupport",
            mode: .eachChild,
            minimumAgeDays: 0,
            minimumBytes: 10_000_000
        ))

        rules.append(CleanupRule(
            id: "xcode.tvOSDeviceSupport",
            category: .xcode,
            risk: .review,
            path: "Library/Developer/Xcode/tvOS DeviceSupport",
            mode: .eachChild,
            minimumAgeDays: 0,
            minimumBytes: 10_000_000
        ))

        rules.append(CleanupRule(
            id: "xcode.archives",
            category: .xcode,
            risk: .review,
            path: "Library/Developer/Xcode/Archives",
            mode: .eachChild,
            minimumAgeDays: 180,
            minimumBytes: 10_000_000
        ))

        rules.append(CleanupRule(
            id: "xcode.cache",
            category: .xcode,
            risk: .safe,
            path: "Library/Caches/com.apple.dt.Xcode",
            mode: .wholeDirectory,
            minimumAgeDays: 0,
            minimumBytes: 50_000_000,
            ownerBundleIdentifier: "com.apple.dt.Xcode"
        ))

        rules.append(CleanupRule(
            id: "xcode.iosSoftwareUpdates",
            category: .xcode,
            risk: .safe,
            path: "Library/iTunes/iPhone Software Updates",
            mode: .eachChild,
            minimumAgeDays: 7,
            minimumBytes: 100_000_000
        ))

        // ─────────────────────────────────────────────────────────────
        // 시뮬레이터
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "simulator.dyldCache",
            category: .simulators,
            risk: .safe,
            path: "Library/Developer/CoreSimulator/Caches",
            mode: .eachChild,
            minimumAgeDays: 0,
            minimumBytes: 50_000_000
        ))

        // ─────────────────────────────────────────────────────────────
        // 개발 도구 캐시
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "dev.npmCache",
            category: .developerTooling,
            risk: .safe,
            path: ".npm/_cacache",
            mode: .wholeDirectory,
            minimumAgeDays: 7,
            minimumBytes: 50_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.yarnCache",
            category: .developerTooling,
            risk: .safe,
            path: "Library/Caches/Yarn",
            mode: .wholeDirectory,
            minimumAgeDays: 7,
            minimumBytes: 50_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.pnpmStore",
            category: .developerTooling,
            risk: .review,
            path: "Library/pnpm/store",
            mode: .wholeDirectory,
            minimumAgeDays: 30,
            minimumBytes: 100_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.pipCache",
            category: .developerTooling,
            risk: .safe,
            path: "Library/Caches/pip",
            mode: .wholeDirectory,
            minimumAgeDays: 7,
            minimumBytes: 20_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.homebrewCache",
            category: .developerTooling,
            risk: .safe,
            path: "Library/Caches/Homebrew",
            mode: .wholeDirectory,
            minimumAgeDays: 7,
            minimumBytes: 50_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.swiftpmCache",
            category: .developerTooling,
            risk: .safe,
            path: "Library/Caches/org.swift.swiftpm",
            mode: .wholeDirectory,
            minimumAgeDays: 14,
            minimumBytes: 50_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.cocoapodsCache",
            category: .developerTooling,
            risk: .safe,
            path: "Library/Caches/CocoaPods",
            mode: .wholeDirectory,
            minimumAgeDays: 14,
            minimumBytes: 50_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.puppeteerChromium",
            category: .developerTooling,
            risk: .review,
            // 전에는 `.eachChild` 로 버전별 하위 폴더를 겨냥했는데,
            // 하위 폴더가 조건에 안 걸리면 상위 폴더를 잡은 일반 캐시 규칙이 살아남아
            // 560MB 짜리 브라우저 빌드가 '안전' 등급으로 기본 선택됐다.
            // 같은 경로를 겨냥해 겹치게 하고, 중복 정리에서 더 조심스러운 등급이 남게 한다.
            path: "Library/Caches/ms-playwright",
            mode: .wholeDirectory,
            // 확인 등급이라 사용자가 직접 골라야 한다. 그 위에서 나이로 또 숨길 이유가 없다.
            minimumAgeDays: 0,
            minimumBytes: 50_000_000
        ))

        // ─────────────────────────────────────────────────────────────
        // 일반 앱 캐시
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "cache.userCaches",
            category: .userCache,
            risk: .safe,
            path: "Library/Caches",
            mode: .eachChild,
            // 캐시에 나이 조건을 거는 건 말이 안 된다. 캐시는 늘 최근에 바뀐다 — 그게 캐시다.
            // 실제 맥에서 이 조건 때문에 브라우저 캐시 3.5GB 가 목록에 영원히 안 떴다.
            // 대신 '그 앱이 지금 켜져 있는가' 로 판단한다. 그게 진짜 물어야 할 질문이다.
            minimumAgeDays: 0,
            minimumBytes: 20_000_000,
            deniedChildNames: dataBearingCacheDirectories,
            costlyChildNames: costlyCacheDirectories
        ))

        // 주의: 경로에 `*` 가 하나 들어간다. `Library/Containers/<앱>` 자체를 지우면
        // 그 앱의 **데이터가 통째로 날아간다.** 반드시 그 안의 Caches 만 겨냥해야 한다.
        rules.append(CleanupRule(
            id: "cache.containerCaches",
            category: .userCache,
            risk: .safe,
            path: "Library/Containers/*/Data/Library/Caches",
            mode: .wholeDirectory,
            minimumAgeDays: 0,
            minimumBytes: 50_000_000,
            requiresFullDiskAccess: true
        ))


        // ─────────────────────────────────────────────────────────────
        // Application Support 안의 앱 내부 캐시
        //
        // Electron 앱(Claude, Notion, Slack, Discord, VS Code …)은 캐시를
        // `~/Library/Caches` 가 아니라 자기 Application Support 폴더 안에 넣는다.
        // `Library/Caches` 만 보던 규칙들은 이걸 통째로 놓쳤다.
        // 실제 맥에서 Claude 13GB, Notion 2.7GB 가 여기 있었는데 검사 결과에 한 줄도 안 나왔다.
        //
        // 겨냥하는 건 **명백한 캐시 폴더 이름들뿐**이다.
        // `Local Storage` · `IndexedDB` · `Session Storage` 는 실제 데이터라 건드리지 않는다.
        // ─────────────────────────────────────────────────────────────
        let electronCacheFolders = [
            "Cache", "Code Cache", "GPUCache", "DawnCache",
            "DawnGraphiteCache", "DawnWebGPUCache", "ShaderCache",
            "component_crx_cache", "blob_storage",
        ]
        for folder in electronCacheFolders {
            rules.append(CleanupRule(
                id: "appsupport.cache.\(folder.replacingOccurrences(of: " ", with: "-"))",
                textKey: "appsupport.cache",
                textArgument: folder,
                category: .userCache,
                risk: .safe,
                path: "Library/Application Support/*/\(folder)",
                mode: .wholeDirectory,
                // 캐시라서 늘 최근에 바뀐다. 나이로 거르면 아무것도 안 잡힌다.
                minimumAgeDays: 0,
                minimumBytes: 50_000_000
            ))
        }

        // Electron 앱은 한 단계 더 들어간 곳에도 같은 캐시를 만든다
        // (예: `Claude/Partitions/<이름>/Cache`). 와일드카드가 하나뿐이라 흔한 조합만 따로 적는다.
        for app in ["Claude", "Notion", "Slack", "discord", "Code", "Figma"] {
            rules.append(CleanupRule(
                id: "appsupport.partitionCache.\(app)",
                textKey: "appsupport.partitionCache",
                textArgument: app,
                category: .userCache,
                risk: .safe,
                path: "Library/Application Support/\(app)/Partitions/*/Cache",
                mode: .wholeDirectory,
                minimumAgeDays: 0,
                minimumBytes: 50_000_000
            ))
        }


        // ─────────────────────────────────────────────────────────────
        // 동영상 배경화면 에셋
        //
        // 실제 맥에서 14GB 였다. 한 편에 600~900MB 짜리 .mov 가 스무 편 넘게 쌓인다.
        // 한 번 미리보기만 해도 받아지고, 그 뒤로는 안 써도 계속 남는다.
        //
        // 디렉터리를 통째로 지우지 않고 **.mov 파일만** 겨냥한다.
        // 옆에 있는 설정 파일까지 날려서 배경화면 설정이 깨지는 걸 피하려는 것이다.
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "wallpaper.aerialVideos",
            category: .largeFiles,
            risk: .review,
            path: "Library/Application Support/com.apple.wallpaper/aerials/videos",
            mode: .filesOnly,
            minimumAgeDays: 0,
            minimumBytes: 100_000_000,
            allowedExtensions: ["mov"]
        ))

        // ─────────────────────────────────────────────────────────────
        // Flutter · Dart · Android
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "dev.pubCache",
            category: .developerTooling,
            risk: .review,
            path: ".pub-cache",
            mode: .wholeDirectory,
            minimumAgeDays: 0,
            minimumBytes: 200_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.gradleCache",
            category: .developerTooling,
            risk: .review,
            path: ".gradle/caches",
            mode: .wholeDirectory,
            minimumAgeDays: 30,
            minimumBytes: 200_000_000
        ))

        rules.append(CleanupRule(
            id: "dev.flutterEngineCache",
            category: .developerTooling,
            risk: .review,
            path: "Library/Caches/flutter_engine",
            mode: .wholeDirectory,
            minimumAgeDays: 30,
            minimumBytes: 100_000_000
        ))

        // ─────────────────────────────────────────────────────────────
        // 로그
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "logs.userLogs",
            category: .logs,
            risk: .safe,
            path: "Library/Logs",
            mode: .eachChild,
            minimumAgeDays: 14,
            minimumBytes: 5_000_000,
            // DiagnosticReports 는 아래 전용 규칙이 파일 단위로 더 조심스럽게 다룬다.
            deniedChildNames: ["DiagnosticReports"]
        ))

        rules.append(CleanupRule(
            id: "logs.diagnosticReports",
            category: .logs,
            risk: .safe,
            path: "Library/Logs/DiagnosticReports",
            mode: .filesOnly,
            minimumAgeDays: 30,
            // 하한이 없으면 작은 리포트 수백 건이 목록을 덮는다. 큰 것만 보여준다.
            minimumBytes: 500_000
        ))

        // ─────────────────────────────────────────────────────────────
        // 브라우저
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "browser.chromeCache",
            category: .browser,
            risk: .safe,
            path: "Library/Caches/Google/Chrome",
            mode: .wholeDirectory,
            minimumAgeDays: 0,
            minimumBytes: 50_000_000,
            ownerBundleIdentifier: "com.google.Chrome"
        ))

        rules.append(CleanupRule(
            id: "browser.safariCache",
            category: .browser,
            risk: .safe,
            path: "Library/Containers/com.apple.Safari/Data/Library/Caches",
            mode: .wholeDirectory,
            minimumAgeDays: 0,
            minimumBytes: 50_000_000,
            requiresFullDiskAccess: true,
            ownerBundleIdentifier: "com.apple.Safari"
        ))

        rules.append(CleanupRule(
            id: "browser.firefoxCache",
            category: .browser,
            risk: .safe,
            path: "Library/Caches/Firefox",
            mode: .wholeDirectory,
            minimumAgeDays: 0,
            minimumBytes: 50_000_000,
            ownerBundleIdentifier: "org.mozilla.firefox"
        ))

        // ─────────────────────────────────────────────────────────────
        // 메일
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "mail.downloads",
            category: .mail,
            risk: .safe,
            path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            mode: .eachChild,
            minimumAgeDays: 30,
            minimumBytes: 1_000_000,
            requiresFullDiskAccess: true,
            ownerBundleIdentifier: "com.apple.mail"
        ))

        // ─────────────────────────────────────────────────────────────
        // 다운로드 — 휴지통으로만, 항목별 선택
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "downloads.oldInstallers",
            category: .downloads,
            risk: .review,
            path: "Downloads",
            mode: .filesOnly,
            minimumAgeDays: 90,
            minimumBytes: 20_000_000,
            // 문서·사진·영상은 절대 후보로 잡지 않는다. 설치용 파일 확장자만 본다.
            allowedExtensions: ["dmg", "pkg", "iso", "msi", "xip"]
        ))

        // ─────────────────────────────────────────────────────────────
        // 안내 전용 — 앱이 손대지 않는다
        // ─────────────────────────────────────────────────────────────
        rules.append(CleanupRule(
            id: "advice.quicklookThumbnails",
            category: .userCache,
            risk: .advisory,
            path: "/private/var/folders",
            mode: .wholeDirectory,
            removal: .adviseOnly,
            minimumAgeDays: 0,
            minimumBytes: 0,
            suggestedCommand: "qlmanage -r cache"
        ))

        return rules
    }
}
