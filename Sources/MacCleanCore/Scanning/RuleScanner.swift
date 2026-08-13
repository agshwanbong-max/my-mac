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
                let result = scan(
                    rule: rule, root: root.url, wildcardMatch: root.wildcardMatch,
                    context: context, guardian: guardian, isCancelled: isCancelled
                )
                findings.append(contentsOf: result.findings)
                warnings.append(contentsOf: result.warnings)
            }
        }

        return (findings, warnings)
    }

    /// 후보 제목.
    ///
    /// 와일드카드로 편 규칙은 `*` 가 맞은 이름(앱 폴더명)을 앞에 붙인다.
    /// 안 그러면 `Library/Application Support/*/Cache` 규칙이 만든 후보들이
    /// 전부 "앱 내부 캐시" 라는 같은 제목으로 늘어서서 어느 앱 것인지 알 수 없다.
    static func title(rule: CleanupRule, target: URL, wildcardMatch: String?) -> String {
        guard rule.mode == .wholeDirectory else { return target.lastPathComponent }
        if let match = wildcardMatch { return "\(match) — \(rule.title)" }
        return rule.title
    }

    /// 자식 이름 비교. **접두사로 맞춘다.**
    ///
    /// 앱들이 `Adobe Camera Raw 2` 처럼 폴더 이름에 버전을 붙인다.
    /// 정확히 일치로 비교하면 그런 것들이 차단 목록을 그대로 빠져나간다 (실제로 그랬다).
    /// 과하게 걸리는 쪽이 안전한 방향이라 접두사를 쓴다.
    static func matches(_ name: String, _ entries: Set<String>) -> Bool {
        for entry in entries where name == entry || name.hasPrefix(entry) {
            return true
        }
        return false
    }

    // MARK: - 경로에 들어 있는 단일 `*` 확장

    /// `Library/Containers/*/Data/Library/Caches` 처럼 `*` 가 하나 들어간 경로를 실제 경로 목록으로 편다.
    /// `*` 는 **한 단계 디렉터리 이름 하나**만 대신한다. 재귀 글롭은 지원하지 않는다 — 의도한 제한이다.
    /// 편 결과와, `*` 가 실제로 무엇에 맞았는지를 같이 돌려준다.
    /// 맞은 이름(보통 앱 폴더명)이 없으면 후보 제목이 전부 "Cache" 로 똑같아져 구분이 안 된다.
    struct ExpandedRoot {
        let url: URL
        let wildcardMatch: String?
    }

    private func expandRoots(rule: CleanupRule, context: ScanContext) -> [ExpandedRoot] {
        guard rule.path.contains("*") else {
            let root = context.paths.resolve(rule.path)
            return FileManager.default.fileExists(atPath: root.path) ? [ExpandedRoot(url: root, wildcardMatch: nil)] : []
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

        var results: [ExpandedRoot] = []
        for child in children {
            let candidate = suffix.isEmpty ? child : child.appendingPathComponent(suffix)
            if FileManager.default.fileExists(atPath: candidate.path) {
                results.append(ExpandedRoot(
                    url: candidate.standardizedFileURL,
                    wildcardMatch: child.lastPathComponent
                ))
            }
        }
        return results
    }

    // MARK: - 왜 걸러졌는지 세기

    /// 규칙이 후보를 걸러낸 이유를 센다.
    ///
    /// 이게 필요해진 이유: 실제 맥에서 `iOS DeviceSupport` 17GB 가 검사 결과에
    /// **한 줄도 안 나왔다.** 규칙은 멀쩡히 있었는데 "최근 30일 이내 변경" 필터에
    /// 전부 걸려서 조용히 사라진 것이다.
    /// 화면에서는 "그 폴더에 아무것도 없음" 과 "전부 걸러냄" 이 똑같아 보였다.
    /// 그 둘은 완전히 다른 이야기이므로, 걸러낸 게 있으면 그 사실을 말해준다.
    struct SkipTally {
        var byAge = 0
        var byAgeBytes: Int64 = 0
        var bySize = 0
        var byGuard = 0
        var byRunningApp = 0

        var skippedAnything: Bool { byAge > 0 || bySize > 0 || byGuard > 0 || byRunningApp > 0 }
    }

    private func scan(
        rule: CleanupRule,
        root: URL,
        wildcardMatch: String?,
        context: ScanContext,
        guardian: PathGuard,
        isCancelled: () -> Bool
    ) -> (findings: [Finding], warnings: [ScanWarning]) {
        let constraints = rule.constraints(root: root)
        var tally = SkipTally()
        let findings = collect(
            rule: rule, root: root, wildcardMatch: wildcardMatch, constraints: constraints,
            context: context, guardian: guardian, tally: &tally, isCancelled: isCancelled
        )
        return (findings, warnings(for: rule, tally: tally, foundCount: findings.count))
    }

    /// 걸러낸 게 의미 있는 양이면 사용자에게 알린다.
    private func warnings(for rule: CleanupRule, tally: SkipTally, foundCount: Int) -> [ScanWarning] {
        guard tally.skippedAnything else { return [] }

        var messages: [ScanWarning] = []

        // 크기·관문 때문에 걸러진 건 정상 동작이라 굳이 말하지 않는다.
        // 문제가 되는 건 "최근에 손댔다" 는 이유로 큰 덩어리가 통째로 사라지는 경우다.
        if tally.byAge > 0, tally.byAgeBytes >= 500_000_000 {
            messages.append(ScanWarning(
                ruleID: rule.id,
                message: "'\(rule.title)' 에서 \(tally.byAge)개(\(ByteFormat.string(tally.byAgeBytes)))를 "
                    + "최근 \(rule.minimumAgeDays)일 이내에 변경됐다는 이유로 제외했습니다."
                    + (foundCount == 0 ? " 그래서 이 항목은 목록에 나오지 않습니다." : "")
            ))
        }

        if tally.byRunningApp > 0 {
            messages.append(ScanWarning(
                ruleID: rule.id,
                message: "'\(rule.title)' 에서 \(tally.byRunningApp)개를 해당 앱이 실행 중이라 건너뛰었습니다. "
                    + "그 앱을 종료하고 다시 검사하면 정리할 수 있습니다."
            ))
        }

        return messages
    }

    // MARK: -

    private func collect(
        rule: CleanupRule,
        root: URL,
        wildcardMatch: String?,
        constraints: RuleConstraints,
        context: ScanContext,
        guardian: PathGuard,
        tally: inout SkipTally,
        isCancelled: () -> Bool
    ) -> [Finding] {
        switch rule.mode {
        case .wholeDirectory:
            guard let finding = makeFinding(
                rule: rule, target: root, constraints: constraints, wildcardMatch: wildcardMatch,
                context: context, guardian: guardian, isCostly: false, tally: &tally, isCancelled: isCancelled
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

                // 캐시 폴더 이름은 대개 그 앱의 번들 ID 다 (`com.google.Chrome` 처럼).
                // 그 앱이 지금 켜져 있으면 캐시를 건드리지 않는다.
                //
                // 이게 나이 필터를 대신한다. 캐시에 "최근에 바뀌었나" 를 묻는 건 말이 안 된다 —
                // 캐시는 늘 최근에 바뀐다. 실제로 그 필터 때문에 브라우저 캐시 3.5GB 가
                // 목록에 영원히 안 뜨고 있었다. 정작 물어야 할 건 "지금 쓰는 중인가" 다.
                if name.contains("."), context.isRunning(name) {
                    tally.byRunningApp += 1
                    continue
                }

                if RuleScanner.matches(name, rule.deniedChildNames) { continue }
                if !rule.allowedChildNames.isEmpty && !rule.allowedChildNames.contains(name) { continue }
                let isCostly = RuleScanner.matches(name, rule.costlyChildNames)

                if rule.mode == .filesOnly {
                    let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDirectory { continue }
                }

                if !rule.allowedExtensions.isEmpty {
                    let ext = child.pathExtension.lowercased()
                    if !rule.allowedExtensions.contains(ext) { continue }
                }

                if let finding = makeFinding(
                    rule: rule, target: child, constraints: constraints, wildcardMatch: wildcardMatch,
                    context: context, guardian: guardian, isCostly: isCostly, tally: &tally, isCancelled: isCancelled
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
        wildcardMatch: String?,
        context: ScanContext,
        guardian: PathGuard,
        isCostly: Bool,
        tally: inout SkipTally,
        isCancelled: () -> Bool
    ) -> Finding? {
        // 관문을 못 지나면 조용히 버린다. 후보 목록에 아예 올리지 않는다.
        let decision = guardian.evaluate(target, constraints: constraints)
        guard decision.allowed else {
            tally.byGuard += 1
            return nil
        }

        let measurement = usage.measure(target, isCancelled: isCancelled)
        guard measurement.allocatedBytes >= rule.minimumBytes else {
            tally.bySize += 1
            return nil
        }

        let age = context.ageInDays(of: measurement.newestModification)
        guard age >= rule.minimumAgeDays else {
            tally.byAge += 1
            tally.byAgeBytes += measurement.allocatedBytes
            return nil
        }

        var detail = rule.explanation
        if rule.mode != .wholeDirectory {
            detail = "\(target.lastPathComponent) — \(rule.explanation)"
        }
        detail += " (\(context.paths.abbreviate(target)))"
        if measurement.incomplete {
            detail += " (일부 항목을 읽지 못해 실제 크기는 이보다 클 수 있습니다.)"
        }

        // 재생성 비용이 큰 항목은 등급을 낮춰 기본 선택에서 빼고, 결과 설명도 덧붙인다.
        let risk = isCostly ? max(rule.risk, RiskLevel.review) : rule.risk
        let consequence = isCostly
            ? rule.consequence + " 이 항목은 다시 만드는 데 시간이 오래 걸리거나 수백 MB 를 다시 내려받아야 합니다."
            : rule.consequence

        return Finding(
            id: "\(rule.id)|\(target.path)",
            ruleID: rule.id,
            category: rule.category,
            risk: risk,
            title: RuleScanner.title(rule: rule, target: target, wildcardMatch: wildcardMatch),
            detail: detail,
            consequence: consequence,
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
