import Foundation

/// 내용이 완전히 같은 파일들을 찾는다.
///
/// **이 앱에서 가장 위험한 기능이다.** 다른 스캐너는 캐시와 빌드 산출물만 건드리는데
/// 여기는 사용자 문서를 대상으로 한다.
///
/// 그런데 중복에는 다른 것들에 없는 성질이 하나 있다.
/// **똑같은 사본이 남아 있으면 지워도 잃는 게 없다.** 정보가 보존된다.
/// 그래서 안전의 기준을 다르게 잡았다 — "지워도 되는 파일인가" 가 아니라
/// "사본이 확실히 남는가" 를 증명하는 쪽으로.
///
/// 그 증명은 `Finding.mustSurvive` 에 실려 실행기까지 간다.
/// 실행기는 지우기 직전에 **지울 파일과 남길 파일을 둘 다 다시 해시해서**
/// 기록된 값과 셋이 일치할 때만 진행한다. 하나라도 어긋나면 지우지 않는다.
///
/// 찾는 방법은 세 번에 나눠서 좁힌다. 전체 해시는 비싸기 때문이다.
/// 1. 크기가 같은 것끼리 모은다 (공짜)
/// 2. 앞 4KB 해시로 다시 나눈다 (거의 공짜, 대부분 여기서 걸러진다)
/// 3. 남은 것만 전체 해시한다
public struct DuplicateScanner: Scanner {

    public let identifier = "duplicates"

    private let minimumBytes: Int64
    private let maximumGroups: Int
    private let maximumFiles: Int

    public init(
        minimumBytes: Int64 = 1_000_000,
        maximumGroups: Int = 40,
        maximumFiles: Int = 200_000
    ) {
        self.minimumBytes = minimumBytes
        self.maximumGroups = maximumGroups
        self.maximumFiles = maximumFiles
    }

    /// 중복이 실제로 쌓이는 곳들.
    ///
    /// `~/Library` 는 일부러 뺐다. 캐시에는 중복이 널려 있지만 그건 앱이 알아서 관리하는 것이고,
    /// 이미 다른 규칙들이 통째로 다룬다. 여기서 다시 건드리면 겹치기만 한다.
    static let searchRoots = ["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"]

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        let protected = ProtectedPaths(paths: context.paths)

        // ── 1단계: 크기로 모으기 ──────────────────────────────────────
        var bySize: [Int64: [URL]] = [:]
        var visited = 0
        var truncated = false

        for relative in DuplicateScanner.searchRoots {
            if isCancelled() || truncated { break }
            let root = context.paths.resolve(relative)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            context.progress.note(L("progress.duplicateCandidates", relative))

            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey],
                options: [],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited > maximumFiles || isCancelled() {
                    truncated = true
                    break
                }

                guard let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey]
                ) else { continue }

                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                // 사진 보관함 같은 번들 안은 들어가지 않는다. 안의 파일은 앱이 관리하는 것이고,
                // 겉보기에 중복이어도 지우면 보관함이 깨진다.
                if values.isDirectory == true {
                    if values.isPackage == true || protected.matchedUnwaivableRule(for: url) != nil {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                let size = Int64(values.fileSize ?? 0)
                guard size >= minimumBytes else { continue }
                guard protected.matchedUnwaivableRule(for: url) == nil else { continue }

                bySize[size, default: []].append(url)
            }
        }

        // ── 2단계: 앞부분 해시로 좁히기 ───────────────────────────────
        var candidates: [[URL]] = []
        for (_, group) in bySize where group.count >= 2 {
            if isCancelled() { break }
            var byPrefix: [String: [URL]] = [:]
            for url in group {
                guard let digest = FileHash.sha256(of: url, prefixBytes: 4096) else { continue }
                byPrefix[digest, default: []].append(url)
            }
            for (_, narrowed) in byPrefix where narrowed.count >= 2 {
                candidates.append(narrowed)
            }
        }

        // ── 3단계: 전체 해시로 확정 ───────────────────────────────────
        context.progress.note(L("progress.duplicateVerify", candidates.count))
        var confirmed: [(digest: String, urls: [URL], size: Int64)] = []

        for group in candidates {
            if isCancelled() { break }
            var byDigest: [String: [URL]] = [:]
            for url in group {
                guard let digest = FileHash.sha256(of: url) else { continue }
                byDigest[digest, default: []].append(url)
            }
            for (digest, identical) in byDigest where identical.count >= 2 {
                let size = Int64((try? identical[0].resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                confirmed.append((digest, identical, size))
            }
        }

        // 확보량이 큰 묶음부터. (사본 수 - 1) × 파일 크기.
        confirmed.sort { ($0.urls.count - 1) * Int($0.size) > ($1.urls.count - 1) * Int($1.size) }

        // ── 후보 만들기 ───────────────────────────────────────────────
        var findings: [Finding] = []
        let guardian = PathGuard(paths: context.paths)

        for group in confirmed.prefix(maximumGroups) {
            let keeper = DuplicateScanner.chooseKeeper(from: group.urls, paths: context.paths)
            let requirement = MustSurvive(path: keeper, sha256: group.digest)

            for victim in group.urls where victim != keeper {
                // 지울 파일이 있는 최상위 사용자 폴더만 예외로 연다.
                // 이 폴더들은 평소 보호 대상이지만, 중복은 사본이 남으므로 예외를 둘 근거가 있다.
                // 이름 기반 차단(.git, 사진 보관함 번들)은 여기서도 그대로 막힌다.
                guard let root = DuplicateScanner.userRoot(of: victim, paths: context.paths) else { continue }

                let constraints = RuleConstraints(
                    allowedRoots: [root],
                    minimumDepth: root.standardizedFileURL.pathComponents.count,
                    exemptProtectedPrefix: root
                )
                guard guardian.evaluate(victim, constraints: constraints).allowed else { continue }

                findings.append(Finding(
                    id: "duplicate|\(victim.path)",
                    ruleID: "duplicates.identical",
                    category: .duplicates,
                    risk: .review,
                    title: victim.lastPathComponent,
                    detail: "\(context.paths.abbreviate(victim.deletingLastPathComponent()))"
                        + L("duplicate.oneOf", group.urls.count),
                    consequence: """
                    내용이 한 바이트도 다르지 않은 사본이 남습니다:
                    \(context.paths.abbreviate(keeper))

                    지우기 직전에 두 파일을 다시 확인합니다. 그 사이 사본이 사라졌거나
                    내용이 바뀌었으면 지우지 않습니다. 휴지통으로 가므로 되돌릴 수도 있습니다.
                    """,
                    path: victim,
                    reclaimableBytes: group.size,
                    itemCount: 1,
                    lastModified: (try? victim.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate,
                    removal: .trashItem,
                    mustSurvive: requirement,
                    constraints: constraints
                ))
            }
        }

        var warnings: [ScanWarning] = []
        if truncated {
            warnings.append(ScanWarning(
                ruleID: "duplicates",
                message: L("warn.duplicateIncomplete")
            ))
        }
        if confirmed.count > maximumGroups {
            warnings.append(ScanWarning(
                ruleID: "duplicates",
                message: L("warn.duplicateTruncated", confirmed.count, maximumGroups)
            ))
        }

        return (findings, warnings)
    }

    // MARK: -

    /// 어느 사본을 남길 것인가.
    ///
    /// 원본일 가능성이 높은 쪽을 남긴다. 순서대로:
    /// 1. 다운로드 폴더 **밖**에 있는 것 — 다운로드 폴더는 대개 받은 사본이 쌓이는 곳이다
    /// 2. 경로가 짧은 것 — 깊이 묻힌 사본보다 제자리에 있을 확률이 높다
    /// 3. 오래된 것 — 나중에 생긴 쪽이 사본일 가능성이 높다
    ///
    /// 완벽한 판단은 불가능하다. 그래서 사용자에게 어느 쪽을 남기는지 항상 보여주고,
    /// 기본 선택도 하지 않는다.
    static func chooseKeeper(from urls: [URL], paths: UserPaths) -> URL {
        let downloads = paths.resolve("Downloads").path

        return urls.min { lhs, rhs in
            let lhsDownloaded = lhs.path.hasPrefix(downloads + "/")
            let rhsDownloaded = rhs.path.hasPrefix(downloads + "/")
            if lhsDownloaded != rhsDownloaded { return !lhsDownloaded }

            let lhsDepth = lhs.pathComponents.count
            let rhsDepth = rhs.pathComponents.count
            if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }

            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantFuture
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }

            return lhs.path < rhs.path
        } ?? urls[0]
    }

    /// 이 파일이 어느 최상위 사용자 폴더에 있는지.
    static func userRoot(of url: URL, paths: UserPaths) -> URL? {
        for relative in DuplicateScanner.searchRoots {
            let root = paths.resolve(relative)
            if url.path.hasPrefix(root.path + "/") { return root }
        }
        return nil
    }
}
