import Foundation

/// 폴더 하나를 열어서 그 안을 보여준다.
///
/// **이 앱의 다른 모든 기능과 성격이 다르다.**
/// 나머지는 전부 `RuleCatalog` 에 미리 검증해 적어둔 경로만 건드린다.
/// 여기는 사용자가 임의의 폴더를 열고 스스로 고른다.
///
/// 왜 필요한가:
/// macOS 의 "시스템 데이터" 에 남는 것들은 대부분 `~/Library/Application Support` 안의
/// 앱별 폴더다. 앱마다 구조가 달라서 미리 규칙을 적어둘 수가 없다.
/// 규칙이 없다고 손도 못 대게 하면, 정작 제일 큰 덩어리 앞에서 앱이 아무것도 못 한다.
///
/// 그래서 열되, 다음을 지킨다.
/// - **관문은 그대로 적용된다.** 문서·사진·iCloud·자격 증명은 여기서도 못 지운다.
/// - **깊이를 요구한다.** 홈 바로 아래(`~/Library` 같은 것)는 통째로 못 지운다.
/// - **언제나 휴지통으로만** 간다. 완전 삭제는 불가능하다.
/// - **항목마다 판정을 붙인다.** 규칙이 없으니 판단 근거를 그만큼 더 보여줘야 한다.
public struct DirectoryBrowser: Sendable {

    /// 폴더 안의 항목 하나.
    public struct Entry: Identifiable, Sendable {
        public var id: String { url.path }
        public let url: URL
        public let name: String
        public let isDirectory: Bool
        public let bytes: Int64
        public let itemCount: Int
        public let modified: Date?

        /// 지워도 되는지에 대한 판정. 규칙이 없는 영역이라 이게 유일한 안내다.
        public let assessment: ImportanceAssessment

        /// 관문을 통과하는가. 통과 못 하면 선택 자체가 불가능하다.
        public let isRemovable: Bool
        /// 통과 못 한 이유.
        public let blockedReason: String?
    }

    private let paths: UserPaths
    private let usage = DiskUsage()

    public init(paths: UserPaths) {
        self.paths = paths
    }

    /// 사용자가 직접 고른 항목에 적용할 관문 제약.
    ///
    /// 허용 루트는 홈 하나뿐이고, **홈보다 두 단계 이상 깊어야** 한다.
    /// 그래야 `~/Library` 나 `~/Downloads` 같은 큰 폴더를 통째로 날리는 사고가 안 난다.
    /// 보호 경로 목록은 여기서도 그대로 살아 있다 — 예외를 열지 않는다.
    public static func constraints(paths: UserPaths) -> RuleConstraints {
        let homeDepth = paths.home.standardizedFileURL.pathComponents.count - 1
        return RuleConstraints(allowedRoots: [paths.home], minimumDepth: homeDepth + 2)
    }

    /// 폴더를 연다. 각 항목의 크기를 재므로 큰 폴더는 몇 초 걸릴 수 있다.
    public func open(
        _ directory: URL,
        isCancelled: () -> Bool = { false }
    ) -> [Entry] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else {
            return []
        }

        let guardian = PathGuard(paths: paths)
        let assessor = ImportanceAssessor(paths: paths)
        let constraints = DirectoryBrowser.constraints(paths: paths)

        var entries: [Entry] = []
        for child in children {
            if isCancelled() { break }

            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isDirectory = values?.isDirectory ?? false
            let measurement = usage.measure(child, isCancelled: isCancelled)
            let decision = guardian.evaluate(child, constraints: constraints)

            entries.append(Entry(
                url: child,
                name: child.lastPathComponent,
                isDirectory: isDirectory,
                bytes: measurement.allocatedBytes,
                itemCount: measurement.fileCount,
                modified: values?.contentModificationDate ?? measurement.newestModification,
                assessment: assessor.assess(child),
                isRemovable: decision.allowed,
                blockedReason: decision.allowed ? nil : "\(decision.reason) [\(decision.gate)]"
            ))
        }

        return entries.sorted { $0.bytes > $1.bytes }
    }

    /// 사용자가 고른 항목을 실행기에 넘길 수 있는 형태로 바꾼다.
    ///
    /// 위험 등급은 무조건 `.review` 다. 규칙이 검증하지 않은 경로라서
    /// "안전" 이라고 말할 근거가 없다. 처리 방식도 무조건 휴지통이다.
    public func finding(for entry: Entry) -> Finding {
        Finding(
            id: "manual|\(entry.url.path)",
            ruleID: "manual.userSelected",
            category: .manualSelection,
            risk: .review,
            title: entry.name,
            detail: paths.abbreviate(entry.url),
            consequence: """
            ⚠️ 이 항목은 이 앱이 미리 검증한 정리 목록에 없습니다. 직접 고르신 것입니다.
            \(entry.assessment.headline)
            지우면: \(entry.assessment.cost)
            휴지통으로 옮기므로 이상하면 되돌릴 수 있습니다.
            """,
            path: entry.url,
            reclaimableBytes: entry.bytes,
            itemCount: entry.itemCount,
            lastModified: entry.modified,
            removal: .trashItem,
            constraints: DirectoryBrowser.constraints(paths: paths)
        )
    }
}
