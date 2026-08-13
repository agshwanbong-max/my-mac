import Foundation

/// `RuleCatalog` 의 데이터 규칙을 실제 후보로 바꾸는 스캐너.
///
/// 전용 스캐너(시뮬레이터·스냅샷 등)를 빼면 대부분의 후보가 여기서 나온다.
public struct RuleScanner: Scanner {

    public let identifier = "rules"

    private let rules: [CleanupRule]
    private let usage = DiskUsage()

    public init(rules: [CleanupRule]) {
        self.rules = rules
    }

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        var findings: [Finding] = []
        var warnings: [ScanWarning] = []
        let guardian = PathGuard(paths: context.paths)

        for rule in rules {
            if isCancelled() { break }

            if rule.requiresFullDiskAccess && !context.hasFullDiskAccess {
                warnings.append(ScanWarning(
                    ruleID: rule.id,
                    message: "'\(rule.title)' 은(는) 전체 디스크 접근 권한이 없어 건너뛰었습니다."
                ))
                continue
            }

            if context.isRunning(rule.ownerBundleIdentifier) {
                warnings.append(ScanWarning(
                    ruleID: rule.id,
                    message: "'\(rule.title)' 은(는) 해당 앱이 실행 중이라 건너뛰었습니다. 앱을 종료한 뒤 다시 검사하세요."
                ))
                continue
            }

            // 안내 전용 규칙은 파일을 재지 않고 설명만 내보낸다.
            if rule.removal == .adviseOnly {
                findings.append(advisoryFinding(for: rule))
                continue
            }

            for root in expandRoots(rule: rule, context: context) {
                if isCancelled() { break }
                findings.append(contentsOf: scan(rule: rule, root: root, context: context, guardian: guardian, isCancelled: isCancelled))
            }
        }

        return (findings, warnings)
    }

    // MARK: - 경로에 들어 있는 단일 `*` 확장

    /// `Library/Containers/*/Data/Library/Caches` 처럼 `*` 가 하나 들어간 경로를 실제 경로 목록으로 편다.
    /// `*` 는 **한 단계 디렉터리 이름 하나**만 대신한다. 재귀 글롭은 지원하지 않는다 — 의도한 제한이다.
    private func expandRoots(rule: CleanupRule, context: ScanContext) -> [URL] {
        guard rule.path.contains("*") else {
            let root = context.paths.resolve(rule.path)
            return FileManager.default.fileExists(atPath: root.path) ? [root] : []
        }

        let parts = rule.path.components(separatedBy: "*")
        guard parts.count == 2 else { return [] }

        let prefix = parts[0].hasSuffix("/") ? String(parts[0].dropLast()) : parts[0]
        var suffix = parts[1]
        if suffix.hasPrefix("/") { suffix.removeFirst() }

        let base = context.paths.resolve(prefix)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for child in children {
            let candidate = suffix.isEmpty ? child : child.appendingPathComponent(suffix)
            if FileManager.default.fileExists(atPath: candidate.path) {
                results.append(candidate.standardizedFileURL)
            }
        }
        return results
    }

    // MARK: -

    private func scan(
        rule: CleanupRule,
        root: URL,
        context: ScanContext,
        guardian: PathGuard,
        isCancelled: () -> Bool
    ) -> [Finding] {
        let constraints = rule.constraints(root: root)

        switch rule.mode {
        case .wholeDirectory:
            guard let finding = makeFinding(
                rule: rule, target: root, constraints: constraints,
                context: context, guardian: guardian, isCancelled: isCancelled
            ) else { return [] }
            return [finding]

        case .eachChild, .filesOnly:
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else {
                return []
            }

            var results: [Finding] = []
            for child in children {
                if isCancelled() { break }

                let name = child.lastPathComponent
                if rule.deniedChildNames.contains(name) { continue }
                if !rule.allowedChildNames.isEmpty && !rule.allowedChildNames.contains(name) { continue }

                if rule.mode == .filesOnly {
                    let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDirectory { continue }
                }

                if !rule.allowedExtensions.isEmpty {
                    let ext = child.pathExtension.lowercased()
                    if !rule.allowedExtensions.contains(ext) { continue }
                }

                if let finding = makeFinding(
                    rule: rule, target: child, constraints: constraints,
                    context: context, guardian: guardian, isCancelled: isCancelled
                ) {
                    results.append(finding)
                }
            }
            return results
        }
    }

    private func makeFinding(
        rule: CleanupRule,
        target: URL,
        constraints: RuleConstraints,
        context: ScanContext,
        guardian: PathGuard,
        isCancelled: () -> Bool
    ) -> Finding? {
        // 관문을 못 지나면 조용히 버린다. 후보 목록에 아예 올리지 않는다.
        let decision = guardian.evaluate(target, constraints: constraints)
        guard decision.allowed else { return nil }

        let measurement = usage.measure(target, isCancelled: isCancelled)
        guard measurement.allocatedBytes >= rule.minimumBytes else { return nil }

        let age = context.ageInDays(of: measurement.newestModification)
        guard age >= rule.minimumAgeDays else { return nil }

        var detail = rule.explanation
        if rule.mode != .wholeDirectory {
            detail = "\(target.lastPathComponent) — \(rule.explanation)"
        }
        if measurement.incomplete {
            detail += " (일부 항목을 읽지 못해 실제 크기는 이보다 클 수 있습니다.)"
        }

        return Finding(
            id: "\(rule.id)|\(target.path)",
            ruleID: rule.id,
            category: rule.category,
            risk: rule.risk,
            title: rule.mode == .wholeDirectory ? rule.title : target.lastPathComponent,
            detail: detail,
            consequence: rule.consequence,
            path: target,
            reclaimableBytes: measurement.allocatedBytes,
            itemCount: measurement.fileCount,
            lastModified: measurement.newestModification,
            removal: rule.removal,
            constraints: constraints
        )
    }

    private func advisoryFinding(for rule: CleanupRule) -> Finding {
        Finding(
            id: "\(rule.id)|advice",
            ruleID: rule.id,
            category: rule.category,
            risk: .advisory,
            title: rule.title,
            detail: rule.explanation,
            consequence: rule.consequence,
            path: nil,
            reclaimableBytes: 0,
            itemCount: 0,
            lastModified: nil,
            removal: .adviseOnly,
            suggestedCommand: rule.suggestedCommand
        )
    }
}
