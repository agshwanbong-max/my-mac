import Foundation

/// 스캔 한 번에 필요한 모든 입력.
///
/// 코어가 AppKit 에 의존하지 않도록, "지금 실행 중인 앱" 같은 UI 계층 정보는
/// 여기에 담아서 주입받는다.
public struct ScanContext: Sendable {
    public let paths: UserPaths
    public let now: Date

    /// 현재 실행 중인 앱의 번들 ID. 실행 중인 앱의 캐시는 후보에서 뺀다.
    public let runningBundleIdentifiers: Set<String>

    /// 전체 디스크 접근 권한이 있는가. 없으면 해당 규칙은 건너뛰고 경고를 남긴다.
    public let hasFullDiskAccess: Bool

    /// node_modules 를 찾을 때 뒤질 디렉터리.
    public let projectSearchRoots: [URL]

    /// 오래 걸리는 스캐너가 진행 상황을 흘려보내는 통로.
    /// 스캐너 단위 진행률만으로는 화면이 멈춘 것처럼 보이기 때문에 필요하다.
    public let progress: ScanProgressReporter

    public init(
        paths: UserPaths,
        now: Date = Date(),
        runningBundleIdentifiers: Set<String> = [],
        hasFullDiskAccess: Bool = true,
        projectSearchRoots: [URL]? = nil,
        progress: ScanProgressReporter = .silent
    ) {
        self.paths = paths
        self.now = now
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.hasFullDiskAccess = hasFullDiskAccess
        self.projectSearchRoots = projectSearchRoots ?? ScanContext.defaultProjectRoots(paths: paths)
        self.progress = progress
    }

    static func defaultProjectRoots(paths: UserPaths) -> [URL] {
        ["Developer", "Projects", "projects", "Code", "code", "src", "Work", "dev", "workspace"]
            .map { paths.resolve($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func isRunning(_ bundleIdentifier: String?) -> Bool {
        guard let identifier = bundleIdentifier else { return false }
        return runningBundleIdentifiers.contains(identifier)
    }

    public func ageInDays(of date: Date?) -> Int {
        guard let date = date else { return Int.max }
        return Int(now.timeIntervalSince(date) / 86_400)
    }
}

/// 스캔 중 사용자에게 알려야 할 일 (권한 부족, 건너뛴 항목 등).
public struct ScanWarning: Codable, Sendable, Identifiable, Hashable {
    public var id: String { ruleID + message }
    public let ruleID: String
    public let message: String

    public init(ruleID: String, message: String) {
        self.ruleID = ruleID
        self.message = message
    }
}

/// 개별 스캐너가 따르는 규약.
public protocol Scanner: Sendable {
    var identifier: String { get }
    func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning])
}
