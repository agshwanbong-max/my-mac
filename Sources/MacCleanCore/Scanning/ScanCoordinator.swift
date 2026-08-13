import Foundation

/// 스캔 한 번의 결과 전체.
public struct ScanReport: Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let volume: VolumeSnapshot
    public let findings: [Finding]
    public let warnings: [ScanWarning]

    public init(
        startedAt: Date,
        finishedAt: Date,
        volume: VolumeSnapshot,
        findings: [Finding],
        warnings: [ScanWarning]
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.volume = volume
        self.findings = findings
        self.warnings = warnings
    }

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    /// 앱이 실제로 지울 수 있는 항목의 합계.
    public var totalReclaimable: Int64 {
        findings.filter { $0.isSelectable }.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public func findings(in category: FindingCategory) -> [Finding] {
        findings.filter { $0.category == category }
    }

    /// 해당 카테고리에서 앱이 실제로 회수할 수 있는 양.
    public func reclaimable(in category: FindingCategory) -> Int64 {
        findings
            .filter { $0.category == category && $0.isSelectable }
            .reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// 저장 공간 막대와 사이드바에서 쓰는, 카테고리별 회수 가능량 (큰 순서).
    ///
    /// 튜플이 아니라 이름 있는 타입인 이유: Swift 는 튜플 원소로 가는 키패스를 지원하지 않아
    /// `ForEach(..., id: \.category)` 가 성립하지 않는다.
    public var categoryTotals: [CategoryTotal] {
        categoriesInOrder
            .map { CategoryTotal(category: $0, bytes: reclaimable(in: $0)) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }

    public var categoriesInOrder: [FindingCategory] {
        let present = Set(findings.map { $0.category })
        return FindingCategory.allCases
            .filter { present.contains($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// 카테고리 하나의 회수 가능량.
public struct CategoryTotal: Identifiable, Sendable, Hashable {
    public let category: FindingCategory
    public let bytes: Int64

    public var id: FindingCategory { category }

    public init(category: FindingCategory, bytes: Int64) {
        self.category = category
        self.bytes = bytes
    }
}

/// 모든 스캐너를 돌리고 결과를 정리한다.
public struct ScanCoordinator: Sendable {

    private let scanners: [Scanner]
    private let probe: VolumeProbe

    public init(scanners: [Scanner], probe: VolumeProbe = VolumeProbe()) {
        self.scanners = scanners
        self.probe = probe
    }

    /// 기본 구성. 규칙 기반 스캐너 + 전용 스캐너들.
    ///
    /// - Parameter deepScan: 홈 전체를 훑어 **용량이 어디에 있는지**와 대용량 파일을 찾는다.
    ///   가장 무거운 스캐너라 기본은 꺼져 있다 (파일 수에 따라 수십 초).
    ///   대신 "정리 후보는 5GB 인데 227GB 는 어디 갔나" 라는 질문에 답할 수 있는 유일한 경로다.
    /// - Parameter findDuplicates: 사용자 폴더에서 내용이 같은 파일을 찾는다.
    ///   파일을 전부 해시해야 해서 가장 느리다. 별도 스위치로 둔 이유다.
    public static func standard(
        paths: UserPaths,
        deepScan: Bool = false,
        findDuplicates: Bool = false
    ) -> ScanCoordinator {
        var scanners: [Scanner] = [
            SystemDataScanner(),
            RuleScanner(rules: RuleCatalog.all(paths: paths)),
            SimulatorScanner(),
            IOSBackupScanner(),
            NodeModulesScanner(),
        ]
        if deepScan {
            scanners.append(SpaceBreakdownScanner())
            // 홈 밖도 재야 macOS 저장 공간 화면의 '시스템 데이터' 숫자와 이어붙일 수 있다.
            scanners.append(SystemAreaScanner())
        }
        if findDuplicates {
            scanners.append(DuplicateScanner())
        }
        return ScanCoordinator(scanners: scanners)
    }

    /// 스캐너 하나의 결과를 task group 으로 옮기기 위한 상자.
    private struct ScannerOutput: Sendable {
        let identifier: String
        let findings: [Finding]
        let warnings: [ScanWarning]
    }

    /// 모든 스캐너를 **동시에** 돌린다.
    ///
    /// 스캐너들은 서로 독립적이고 대부분의 시간을 디스크 대기로 보낸다.
    /// 순차 실행하면 가장 느린 하나가 전체를 붙잡는다.
    ///
    /// - Parameters:
    ///   - progress: 끝난 스캐너 개수와 방금 끝난 스캐너 이름.
    ///     동시에 도는 스캐너들의 "지금 몇 %" 를 정확히 말할 방법이 없어서 **끝난 개수**를 센다.
    ///     세는 건 `for await` 루프 안에서만 하므로 경쟁 상태가 없다.
    ///   - isCancelled: 주기적으로 확인한다. 취소되면 부분 결과를 그대로 돌려준다.
    public func run(
        context: ScanContext,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async -> ScanReport {
        let startedAt = Date()
        let total = scanners.count
        progress(ScanProgress(completed: 0, total: total, detail: "검사를 시작합니다"))

        let outputs: [ScannerOutput] = await withTaskGroup(of: ScannerOutput.self) { group in
            for scanner in scanners {
                group.addTask {
                    let result = scanner.scan(context: context, isCancelled: isCancelled)
                    return ScannerOutput(
                        identifier: scanner.identifier,
                        findings: result.findings,
                        warnings: result.warnings
                    )
                }
            }

            var collected: [ScannerOutput] = []
            for await output in group {
                collected.append(output)
                progress(ScanProgress(
                    completed: collected.count,
                    total: total,
                    detail: "\(output.identifier) 완료"
                ))
            }
            return collected
        }

        return ScanReport(
            startedAt: startedAt,
            finishedAt: Date(),
            volume: probe.snapshot(home: context.paths.home),
            findings: ScanCoordinator.deduplicate(outputs.flatMap { $0.findings }),
            warnings: outputs.flatMap { $0.warnings }
        )
    }

    /// 겹치는 후보를 정리한다.
    ///
    /// 규칙이 겹치는 건 정상이다. 예를 들어 `~/Library/Caches` 를 훑는 일반 규칙과
    /// `~/Library/Caches/Homebrew` 를 겨냥한 전용 규칙은 같은 경로를 두 번 내놓는다.
    /// 그대로 두면 (1) 용량이 이중으로 계산되고 (2) 부모를 지운 뒤 자식을 지우려다 실패한다.
    ///
    /// 정책: **더 구체적인(깊은) 후보를 남기고, 그 조상은 버린다.**
    /// 덜 지우는 쪽으로 기우는 선택이고, 항목에 붙는 설명도 더 정확해진다.
    static func deduplicate(_ findings: [Finding]) -> [Finding] {
        // 안내 전용 항목은 파일을 건드리지 않으므로 겹쳐도 상관없다. 그대로 통과시킨다.
        let advisory = findings.filter { $0.path == nil || $0.removal == .adviseOnly }
        let actionable = findings.filter { $0.path != nil && $0.removal != .adviseOnly }

        // 1) 같은 경로가 여러 번 나오면 하나만 남긴다.
        var byPath: [String: Finding] = [:]
        for finding in actionable {
            guard let path = finding.path?.standardizedFileURL.path else { continue }
            if let existing = byPath[path] {
                // 더 조심스러운 쪽(위험 등급이 높은 쪽)을 남긴다.
                byPath[path] = finding.risk > existing.risk ? finding : existing
            } else {
                byPath[path] = finding
            }
        }

        // 2) 다른 후보의 조상인 항목을 버린다.
        let paths = Array(byPath.keys)
        var kept: [Finding] = []
        for path in paths {
            let isAncestorOfAnother = paths.contains { other in
                other != path && other.hasPrefix(path + "/")
            }
            if isAncestorOfAnother { continue }
            if let finding = byPath[path] { kept.append(finding) }
        }

        return (advisory + kept).sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            return lhs.reclaimableBytes > rhs.reclaimableBytes
        }
    }
}
