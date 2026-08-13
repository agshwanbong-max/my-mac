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
    private static let systemPaths: [(path: String, title: String, hint: String)] = [
        ("/Library/Caches", "/Library/Caches",
         "시스템 전체가 쓰는 캐시입니다. macOS 저장 공간 화면에서는 '시스템 데이터'로 잡힙니다. "
            + "관리자 권한이 필요해 이 앱은 건드리지 않습니다."),
        ("/Library/Application Support", "/Library/Application Support",
         "모든 사용자가 함께 쓰는 앱 데이터입니다. Adobe·가상머신·개발 도구가 여기 크게 자리잡습니다. "
            + "'시스템 데이터'로 잡힙니다."),
        ("/Library/Developer", "/Library/Developer",
         "시스템에 설치된 개발자 도구입니다. Xcode 15 부터는 시뮬레이터 런타임이 여기 들어갑니다. "
            + "Xcode → Settings → Platforms 에서 안 쓰는 버전을 지울 수 있습니다."),
        ("/Library/Logs", "/Library/Logs",
         "시스템 로그입니다. 보통 크지 않습니다."),
        ("/private/var/folders", "/private/var/folders",
         "시스템이 관리하는 임시 폴더입니다. 재부팅하면 상당 부분 정리됩니다. "
            + "'시스템 데이터'로 잡힙니다."),
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
        findings.append(contentsOf: applicationFindings(isCancelled: isCancelled))

        // ── 홈 밖의 시스템 영역 ────────────────────────────────────────
        for entry in SystemAreaScanner.systemPaths {
            if isCancelled() { break }

            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let measurement = usage.measure(url, limit: SystemAreaScanner.nodeLimit, isCancelled: isCancelled)
            guard measurement.allocatedBytes >= 500_000_000 else { continue }

            var detail = "\(measurement.fileCount)개 파일"
            if measurement.incomplete {
                detail += " (권한이나 크기 때문에 일부만 셌습니다 — 실제로는 더 클 수 있습니다)"
            }

            findings.append(Finding(
                id: "systemArea|\(entry.path)",
                ruleID: "advice.systemArea",
                category: .spaceBreakdown,
                risk: .advisory,
                title: entry.title,
                detail: detail,
                consequence: entry.hint,
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

    private func applicationFindings(isCancelled: () -> Bool) -> [Finding] {
        let root = URL(fileURLWithPath: "/Applications")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sized: [(url: URL, bytes: Int64)] = []
        for child in children {
            if isCancelled() { break }
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
                    detail: "설치된 앱 · /Applications",
                    consequence: "macOS 저장 공간 화면의 '응용 프로그램' 칸에 잡힙니다. "
                        + "안 쓰는 앱이면 파인더에서 휴지통으로 옮기세요. 이 앱은 설치된 프로그램을 지우지 않습니다.",
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
            title: "macOS 저장 공간 화면의 칸과 실제 폴더",
            detail: """
            시스템 설정의 저장 공간 화면에 나오는 칸이 각각 어디를 가리키는지입니다.
            어느 숫자를 줄이려는지에 따라 손댈 곳이 다릅니다.
            """,
            consequence: """
            · 개발자  →  ~/Library/Developer
              iOS DeviceSupport, 시뮬레이터, DerivedData. 여기를 지우면 '개발자' 칸이 줄고 '시스템 데이터'는 그대로입니다.

            · 응용 프로그램  →  /Applications
              Xcode 하나가 15~20GB 입니다. 앱을 지워야 줄어듭니다.

            · 시스템 데이터  →  나머지 전부
              ~/Library/Application Support, ~/Library/Caches, ~/Library/Containers,
              /Library, /private/var, 로컬 스냅샷이 여기로 들어갑니다.
              개발자 맥에서 이 칸을 크게 만드는 건 보통 Application Support 입니다 —
              동영상 배경화면, Electron 앱의 데이터, 브라우저 프로필.

            · macOS  →  시스템 볼륨. 건드릴 수 없고 건드릴 필요도 없습니다.
            """,
            path: nil,
            reclaimableBytes: 0,
            itemCount: 0,
            lastModified: nil,
            removal: .adviseOnly
        )
    }
}
