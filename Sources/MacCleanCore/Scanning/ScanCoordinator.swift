import Foundation

/// 스캔 한 번의 결과 전체.
public struct ScanReport: Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let volume: VolumeSnapshot
    public let findings: [Finding]
    public let warnings: [ScanWarning]

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    /// 앱이 실제로 지울 수 있는 항목의 합계.
    public var totalReclaimable: Int64 {
        findings.filter { $0.isSelectable }.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public func findings(in category: FindingCategory) -> [Finding] {
        findings.filter { $0.category == category }
    }

    public var categoriesInOrder: [FindingCategory] {
        let present = Set(findings.map { $0.category })
        return FindingCategory.allCases
            .filter { present.contains($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
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
    public static func standard(paths: UserPaths) -> ScanCoordinator {
        ScanCoordinator(scanners: [
            SystemDataScanner(),
            RuleScanner(rules: RuleCatalog.all(paths: paths)),
            SimulatorScanner(),
            IOSBackupScanner(),
            NodeModulesScanner(),
            LargeFileScanner(),
        ])
    }

    public func run(context: ScanContext, isCancelled: () -> Bool = { false }) -> ScanReport {
        let startedAt = Date()
        var findings: [Finding] = []
        var warnings: [ScanWarning] = []

        for scanner in scanners {
            if isCancelled() { break }
            let result = scanner.scan(context: context, isCancelled: isCancelled)
            findings.append(contentsOf: result.findings)
            warnings.append(contentsOf: result.warnings)
        }

        return ScanReport(
            startedAt: startedAt,
            finishedAt: Date(),
            volume: probe.snapshot(home: context.paths.home),
            findings: ScanCoordinator.deduplicate(findings),
            warnings: warnings
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
