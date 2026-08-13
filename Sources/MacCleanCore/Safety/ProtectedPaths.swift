import Foundation

/// 무슨 일이 있어도 건드리면 안 되는 경로 목록.
///
/// 설계 원칙: **이 목록은 규칙(`CleanupRule`)이 덮어쓸 수 없다.**
/// 규칙이 아무리 "여기 지워도 돼" 라고 주장해도 `PathGuard` 는 이 목록을 먼저 본다.
/// 새 정리 규칙을 추가하다가 실수해도 사용자 데이터까지는 못 가게 만드는 마지막 방어선이다.
public struct ProtectedPaths: Sendable {

    // MARK: - 절대 경로 (시스템 영역)

    /// 시스템 소유 영역. 사용자 권한으로는 어차피 대부분 못 지우지만, 명시적으로 막아둔다.
    public static let systemPrefixes: [String] = [
        "/System",
        "/Library/Apple",
        "/Library/Developer/CommandLineTools",
        "/Library/Extensions",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
        "/Library/Preferences",
        "/Library/Keychains",
        "/bin",
        "/sbin",
        "/usr/bin",
        "/usr/lib",
        "/usr/libexec",
        "/usr/sbin",
        "/usr/share",
        "/Applications",
        "/cores",
        "/dev",
        "/private/etc",
        "/private/var/db",
        "/private/var/vm",       // sleepimage / swapfile — 시스템이 관리한다
        "/opt/homebrew/bin",
        "/opt/homebrew/Cellar",
        "/Volumes",              // 외장/네트워크 볼륨은 기본적으로 대상 아님
    ]

    // MARK: - 홈 상대 경로 (사용자 데이터)

    /// 사용자가 만든 것, 유일본일 수 있는 것, 클라우드와 동기화되는 것.
    ///
    /// `~/Downloads` 는 여기 없다 — 휴지통으로 되돌릴 수 있는 방식(`.trashItem`)으로만,
    /// 그리고 사용자가 항목마다 직접 고를 때만 처리한다.
    public static let homeRelativePrefixes: [String] = [
        "Documents",
        "Desktop",
        "Movies",
        "Music",
        "Pictures",
        "Public",
        "Sites",
        "Applications",

        // 클라우드 동기화 영역 — 여기서 지우면 클라우드에서도 지워진다.
        "Library/Mobile Documents",      // iCloud Drive
        "Library/CloudStorage",          // Dropbox / OneDrive / Google Drive 마운트
        "Dropbox",
        "Google Drive",
        "OneDrive",

        // 자격 증명 · 설정 · 메시지
        "Library/Keychains",
        "Library/Preferences",
        "Library/Messages",
        "Library/Mail",                  // Mail Downloads 만 규칙에서 예외 처리
        "Library/Safari",                // 방문 기록 · 북마크 · 읽기 목록
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/Knowledge",
        "Library/Application Support/com.apple.sharedfilelist",
        "Library/Application Support/MobileSync/Backup",  // iOS 백업은 전용 스캐너가 review 로만 다룬다
        "Library/Group Containers",
        "Library/IdentityServices",
        "Library/Photos",
        "Library/Suggestions",
        "Library/Sharing",
        "Library/Accounts",
        "Library/Autosave Information",
        "Library/Calendars",
        "Library/Reminders",
        "Library/Passes",
        "Library/PersonalizationPortrait",
        "Library/Metadata/CoreSpotlight",

        // 개발자 자격증명 · 서명
        "Library/MobileDevice/Provisioning Profiles",
        ".ssh",
        ".gnupg",
        ".aws",
        ".config/gcloud",
        ".kube",
        ".docker/config.json",
        ".netrc",
        ".gitconfig",
    ]

    // MARK: - 이름 기반 차단

    /// 경로 어느 위치에 있든 이 이름의 디렉터리/파일 안으로는 들어가지 않는다.
    public static let forbiddenComponents: Set<String> = [
        ".git",
        ".hg",
        ".svn",
        ".ssh",
        ".gnupg",
        "Keychains",
        "Provisioning Profiles",
    ]

    /// 이 확장자를 가진 번들은 통째로 사용자 데이터로 취급한다. 안으로 들어가지도, 지우지도 않는다.
    ///
    /// 주의: `dmg` / `pkg` 는 일부러 빼놨다. 다운로드 폴더에 남은 설치 파일을
    /// 휴지통으로 보내는 건 이 앱의 정상 기능이다.
    /// `app` 이 들어있어서 `~/Library/Caches/com.example.app` 같은 캐시가
    /// 덩달아 건너뛰어질 수 있는데, 그건 의도한 보수적 오탐이다 — 못 지우는 쪽이 안전하다.
    public static let forbiddenBundleExtensions: Set<String> = [
        "photoslibrary",
        "musiclibrary",
        "tvlibrary",
        "aplibrary",
        "fcpbundle",       // Final Cut
        "lrlibrary",       // Lightroom
        "sparsebundle",
        "band",            // GarageBand
        "logicx",
        "app",             // 앱 번들 내부를 헤집지 않는다
    ]

    // MARK: -

    public let home: URL
    private let absoluteDenyPrefixes: [String]

    public init(paths: UserPaths) {
        self.home = paths.home
        var prefixes = ProtectedPaths.systemPrefixes
        for relative in ProtectedPaths.homeRelativePrefixes {
            prefixes.append(paths.resolve(relative).path)
        }
        self.absoluteDenyPrefixes = prefixes
    }

    /// 해당 경로가 보호 대상인지. 보호 경로 **자신과 그 하위 전부**가 대상이다.
    public func matchedDenyRule(for url: URL) -> String? {
        let path = url.standardizedFileURL.path

        for prefix in absoluteDenyPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") {
                return prefix
            }
        }

        for component in url.pathComponents {
            if ProtectedPaths.forbiddenComponents.contains(component) {
                return "경로에 보호 대상 이름 '\(component)' 포함"
            }
            let ext = (component as NSString).pathExtension.lowercased()
            if !ext.isEmpty, ProtectedPaths.forbiddenBundleExtensions.contains(ext) {
                return "보호 대상 번들 '\(component)' 내부"
            }
        }

        return nil
    }
}
