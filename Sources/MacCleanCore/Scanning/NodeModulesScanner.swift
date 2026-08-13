import Foundation

/// 오랫동안 손대지 않은 `node_modules` 를 찾는다.
///
/// 웹 개발을 하면 프로젝트마다 수백 MB 씩 쌓이고, 끝난 프로젝트의 것도 그대로 남는다.
///
/// 안전 장치가 여러 겹 걸려 있다.
/// - 디렉터리 이름이 정확히 `node_modules` 여야 한다
/// - 같은 폴더에 `package.json` 이 있어야 한다 (진짜 프로젝트라는 증거)
/// - 마지막 수정 후 기본 90일이 지나야 한다
/// - 클라우드 동기화 폴더 안이면 제외된다 (`PathGuard` 가 막는다)
/// - 언제나 `.review` 이고, 언제나 휴지통으로만 보낸다
public struct NodeModulesScanner: Scanner {

    public let identifier = "nodeModules"

    private let usage = DiskUsage()
    private let minimumAgeDays: Int
    private let minimumBytes: Int64
    /// 프로젝트 루트를 찾아 내려갈 최대 깊이. 홈 전체를 훑지 않기 위한 제한.
    private let maximumDepth: Int

    public init(minimumAgeDays: Int = 90, minimumBytes: Int64 = 50_000_000, maximumDepth: Int = 4) {
        self.minimumAgeDays = minimumAgeDays
        self.minimumBytes = minimumBytes
        self.maximumDepth = maximumDepth
    }

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        var findings: [Finding] = []
        let guardian = PathGuard(paths: context.paths)

        for root in context.projectSearchRoots {
            if isCancelled() { break }
            findings.append(contentsOf: search(
                directory: root,
                searchRoot: root,
                depth: 0,
                context: context,
                guardian: guardian,
                isCancelled: isCancelled
            ))
        }

        return (findings, [])
    }

    private func search(
        directory: URL,
        searchRoot: URL,
        depth: Int,
        context: ScanContext,
        guardian: PathGuard,
        isCancelled: () -> Bool
    ) -> [Finding] {
        guard depth <= maximumDepth, !isCancelled() else { return [] }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [Finding] = []

        // 이 폴더가 프로젝트 루트인가? (package.json + node_modules 가 나란히 있는가)
        let names = Set(children.map { $0.lastPathComponent })
        if names.contains("node_modules") && names.contains("package.json") {
            let target = directory.appendingPathComponent("node_modules")
            if let finding = makeFinding(target: target, context: context, guardian: guardian, isCancelled: isCancelled) {
                results.append(finding)
            }
            // 프로젝트 안으로 더 들어가지 않는다. 중첩 node_modules 는 부모가 통째로 처리한다.
            return results
        }

        for child in children {
            if isCancelled() { break }
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            if child.lastPathComponent == "node_modules" { continue }

            results.append(contentsOf: search(
                directory: child,
                searchRoot: searchRoot,
                depth: depth + 1,
                context: context,
                guardian: guardian,
                isCancelled: isCancelled
            ))
        }

        return results
    }

    private func makeFinding(
        target: URL,
        context: ScanContext,
        guardian: PathGuard,
        isCancelled: () -> Bool
    ) -> Finding? {
        let parent = target.deletingLastPathComponent()
        let constraints = RuleConstraints(
            allowedRoots: [parent],
            minimumDepth: target.standardizedFileURL.pathComponents.count - 1
        )
        guard guardian.evaluate(target, constraints: constraints).allowed else { return nil }

        let measurement = usage.measure(target, isCancelled: isCancelled)
        guard measurement.allocatedBytes >= minimumBytes else { return nil }
        guard context.ageInDays(of: measurement.newestModification) >= minimumAgeDays else { return nil }

        let projectName = parent.lastPathComponent
        let days = context.ageInDays(of: measurement.newestModification)

        return Finding(
            id: "nodeModules|\(target.path)",
            ruleID: "dev.nodeModules",
            category: .nodeModules,
            risk: .review,
            title: "\(projectName)/node_modules",
            detail: "\(context.paths.abbreviate(parent)) · 마지막 변경 후 \(days)일 경과",
            consequence: "프로젝트 폴더에서 `npm install` (또는 yarn/pnpm) 을 다시 돌리면 그대로 복구됩니다. "
                + "소스 코드와 package.json 은 건드리지 않습니다.",
            path: target,
            reclaimableBytes: measurement.allocatedBytes,
            itemCount: measurement.fileCount,
            lastModified: measurement.newestModification,
            removal: .trashItem,
            constraints: constraints
        )
    }
}
