import Foundation

/// 홈 **밖**의 용량을 잰다. 전부 읽기 전용이고 전부 `.advisory` 다.
///
/// 이게 필요해진 이유:
/// 홈 안을 다 정리하고도 macOS 저장 공간 화면에는 "시스템 데이터 71GB" 가 그대로 남아 있었다.
/// 사용자 입장에서는 앱이 거짓말을 하는 것처럼 보인다.
///
/// 실제로는 macOS 의 분류와 이 앱이 보던 범위가 어긋나 있었다.
/// - "개발자" 는 `~/Library/Developer` 다. iOS DeviceSupport 를 지우면 **이쪽**이 줄지 시스템 데이터는 그대로다.
/// - "응용 프로그램" 은 `/Applications` 다.
/// - "시스템 데이터" 는 그 어느 칸에도 안 들어간 나머지 전부 — 홈 밖의 `/Library` 도 여기 들어간다.
///
/// 그래서 홈 밖도 재서, 어느 숫자를 줄이려면 무엇을 건드려야 하는지 이어붙여 보여준다.
public struct SystemAreaScanner: Scanner {

    public let identifier = "systemArea"

    /// 홈 밖에서 재볼 곳. 전부 읽기만 한다.
    private static let systemPaths: [(path: String, title: String, hintKey: String)] = [
        ("/Library/Caches", "/Library/Caches", "systemArea.hint.libraryCaches"),
        ("/Library/Application Support", "/Library/Application Support", "systemArea.hint.libraryAppSupport"),
        ("/Library/Developer", "/Library/Developer", "systemArea.hint.libraryDeveloper"),
        ("/Library/Logs", "/Library/Logs", "systemArea.hint.libraryLogs"),
        ("/private/var/folders", "/private/var/folders", "systemArea.hint.varFolders"),
    ]

    /// 홈 밖은 파일이 많아 기본 상한으로는 중간에 끊긴다.
    private static let nodeLimit = 1_500_000

    private let usage = DiskUsage()
    private let maximumApplications: Int

    public init(maximumApplications: Int = 12) {
        self.maximumApplications = maximumApplications
    }

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        var findings: [Finding] = []

        // ── 설치된 앱 ──────────────────────────────────────────────────
        // macOS 저장 공간 화면의 "응용 프로그램" 칸이 이것이다.
        // 개발자 맥에서는 Xcode 하나가 15~20GB 라 이 칸이 통째로 커 보인다.
        findings.append(contentsOf: applicationFindings(context: context, isCancelled: isCancelled))

        // ── 홈 밖의 시스템 영역 ────────────────────────────────────────
        for entry in SystemAreaScanner.systemPaths {
            if isCancelled() { break }

            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            context.progress.note(L("progress.measuring", entry.title))

            let measurement = usage.measure(url, limit: SystemAreaScanner.nodeLimit, isCancelled: isCancelled)
            guard measurement.allocatedBytes >= 500_000_000 else { continue }

            var detail = L("common.fileCount", measurement.fileCount)
            if measurement.incomplete {
                detail += L("scan.partialCount")
            }

            findings.append(Finding(
                id: "systemArea|\(entry.path)",
                ruleID: "advice.systemArea",
                category: .systemData,
                risk: .advisory,
                title: entry.title,
                detail: detail,
                consequence: L(entry.hintKey),
                path: url,
                reclaimableBytes: measurement.allocatedBytes,
                itemCount: measurement.fileCount,
                lastModified: nil,
                removal: .adviseOnly
            ))
        }

        findings.append(categoryMapExplainer())
        return (findings, [])
    }

    // MARK: -

    private func applicationFindings(context: ScanContext, isCancelled: () -> Bool) -> [Finding] {
        let root = URL(fileURLWithPath: "/Applications")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sized: [(url: URL, bytes: Int64)] = []
        for child in children {
            if isCancelled() { break }
            context.progress.note(L("progress.measuringApp", child.deletingPathExtension().lastPathComponent))
            let measurement = usage.measure(child, limit: SystemAreaScanner.nodeLimit, isCancelled: isCancelled)
            if measurement.allocatedBytes >= 500_000_000 {
                sized.append((child, measurement.allocatedBytes))
            }
        }

        return sized
            .sorted { $0.bytes > $1.bytes }
            .prefix(maximumApplications)
            .map { entry in
                Finding(
                    id: "systemArea.app|\(entry.url.path)",
                    ruleID: "advice.applications",
                    category: .spaceBreakdown,
                    risk: .advisory,
                    title: entry.url.deletingPathExtension().lastPathComponent,
                    detail: L("systemArea.installedApp.detail"),
                    consequence: L("systemArea.installedApp.consequence"),
                    path: entry.url,
                    reclaimableBytes: entry.bytes,
                    itemCount: 1,
                    lastModified: nil,
                    removal: .adviseOnly
                )
            }
    }

    /// macOS 의 분류와 실제 폴더를 이어주는 설명.
    ///
    /// 이게 없으면 "DeviceSupport 17GB 를 지웠는데 시스템 데이터가 그대로다" 같은 혼란이 생긴다.
    /// 실제로 그 17GB 는 '시스템 데이터'가 아니라 '개발자' 칸에 들어 있다.
    private func categoryMapExplainer() -> Finding {
        Finding(
            id: "systemArea.categoryMap",
            ruleID: "advice.categoryMap",
            category: .systemDataDiagnosis,
            risk: .advisory,
            title: L("systemArea.categoryMap.title"),
            detail: L("systemArea.categoryMap.detail"),
            consequence: L("systemArea.categoryMap.consequence"),
            path: nil,
            reclaimableBytes: 0,
            itemCount: 0,
            lastModified: nil,
            removal: .adviseOnly
        )
    }
}
