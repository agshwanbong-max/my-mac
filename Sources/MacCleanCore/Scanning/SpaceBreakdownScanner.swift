import Foundation

/// **용량이 어디에 있는지** 알려준다. 정리 대상 목록이 아니라 지도다.
///
/// 이 스캐너가 생긴 이유:
/// 실제 245GB 맥에서 검사를 돌렸더니 227GB 를 쓰고 있는데 앱이 찾아낸 정리 후보는 4.8GB 였다.
/// 나머지 222GB 가 어디 있는지 앱이 한 마디도 못 했다.
/// "무엇을 지울 수 있나" 만 답하고 "내 용량이 어디 갔나" 는 답하지 못하면, 256GB 맥에서는 쓸모가 없다.
///
/// 그리고 그때 대용량 파일 스캐너는 `Library` 를 통째로 건너뛰고 있었다.
/// 하필 그 사용자의 75GB 가 전부 `~/Library` 안에 있었다. 기능이 조용히 아무것도 못 찾고 있었던 것이다.
/// 그래서 지금은 **아무 폴더도 건너뛰지 않는다.** 어차피 읽기만 하고, 전부 `.advisory` 다.
///
/// 홈을 **한 번만** 훑으면서 세 가지를 동시에 모은다.
/// 1. 상위 폴더별 합계 (`~/Library`, `~/Pictures` …)
/// 2. `~/Library` 는 한 단계 더 쪼갠다 — 대부분 여기 몰려 있어서 뭉뚱그리면 의미가 없다
/// 3. 가장 큰 파일들
public struct SpaceBreakdownScanner: Scanner {

    public let identifier = "spaceBreakdown"

    private let largeFileThreshold: Int64
    private let maximumFiles: Int
    private let maximumFolders: Int
    private let maximumNodes: Int

    public init(
        largeFileThreshold: Int64 = 300_000_000,
        maximumFiles: Int = 20,
        maximumFolders: Int = 15,
        maximumNodes: Int = 3_000_000
    ) {
        self.largeFileThreshold = largeFileThreshold
        self.maximumFiles = maximumFiles
        self.maximumFolders = maximumFolders
        self.maximumNodes = maximumNodes
    }

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
            .contentModificationDateKey,
        ]

        let home = context.paths.home.standardizedFileURL
        let homePath = home.path

        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return ([], [])
        }

        var folderTotals: [String: Int64] = [:]
        var folderFileCounts: [String: Int] = [:]
        var bigFiles: [(url: URL, size: Int64, modified: Date?)] = []
        var visited = 0
        var truncated = false

        for case let url as URL in enumerator {
            visited += 1
            if visited > maximumNodes || isCancelled() {
                truncated = true
                break
            }

            guard let values = try? url.resourceValues(forKeys: keys) else { continue }

            // 심볼릭 링크를 따라가면 같은 용량을 두 번 세게 된다.
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == true { continue }

            let size: Int64
            if let total = values.totalFileAllocatedSize {
                size = Int64(total)
            } else if let allocated = values.fileAllocatedSize {
                size = Int64(allocated)
            } else if let logical = values.fileSize {
                size = Int64(logical)
            } else {
                continue
            }

            if let bucket = SpaceBreakdownScanner.bucket(for: url, homePath: homePath) {
                folderTotals[bucket, default: 0] += size
                folderFileCounts[bucket, default: 0] += 1
            }

            if size >= largeFileThreshold {
                bigFiles.append((url, size, values.contentModificationDate))
            }
        }

        var findings: [Finding] = []
        var warnings: [ScanWarning] = []

        if truncated {
            warnings.append(ScanWarning(
                ruleID: "spaceBreakdown",
                message: "파일이 너무 많아 용량 분포를 끝까지 세지 못했습니다. 표시된 값은 실제보다 작습니다."
            ))
        }

        // ── 폴더별 합계 ────────────────────────────────────────────────
        let topFolders = folderTotals
            .sorted { $0.value > $1.value }
            .prefix(maximumFolders)

        for entry in topFolders {
            let url = home.appendingPathComponent(entry.key)
            findings.append(Finding(
                id: "space.folder|\(entry.key)",
                ruleID: "advice.spaceBreakdown",
                category: .spaceBreakdown,
                risk: .advisory,
                title: "~/\(entry.key)",
                detail: "\(folderFileCounts[entry.key] ?? 0)개 파일",
                consequence: SpaceBreakdownScanner.hint(for: entry.key),
                path: url,
                // 안내 항목의 이 값은 '회수 가능량'이 아니라 '차지하는 용량'이다.
                // 합계에는 잡히지 않는다 — 합계는 선택 가능한 항목만 센다.
                reclaimableBytes: entry.value,
                itemCount: folderFileCounts[entry.key] ?? 0,
                lastModified: nil,
                removal: .adviseOnly
            ))
        }

        // ── 큰 파일들 ──────────────────────────────────────────────────
        let topFiles = bigFiles.sorted { $0.size > $1.size }.prefix(maximumFiles)
        for file in topFiles {
            findings.append(Finding(
                id: "space.file|\(file.url.path)",
                ruleID: "advice.largeFiles",
                category: .largeFiles,
                risk: .advisory,
                title: file.url.lastPathComponent,
                detail: context.paths.abbreviate(file.url.deletingLastPathComponent()),
                consequence: "사용자 파일이라 이 앱은 건드리지 않습니다. 파인더에서 직접 확인하고 판단하세요.",
                path: file.url,
                reclaimableBytes: file.size,
                itemCount: 1,
                lastModified: file.modified,
                removal: .adviseOnly
            ))
        }

        return (findings, warnings)
    }

    // MARK: -

    /// 파일 하나를 어느 묶음에 넣을지 정한다.
    ///
    /// 보통은 홈 바로 아래 폴더 이름. 단 `Library` 는 한 단계 더 쪼갠다.
    /// 실제로 홈 용량의 90% 가 `~/Library` 한 곳에 몰려 있는 경우를 봤는데,
    /// 그걸 "Library 75GB" 한 줄로 보여주면 아무 도움이 안 된다.
    static func bucket(for url: URL, homePath: String) -> String? {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return nil }

        let relative = String(path.dropFirst(homePath.count + 1))
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }

        if first == "Library", parts.count >= 2 {
            return "Library/\(parts[1])"
        }
        return String(first)
    }

    /// 그 폴더가 뭔지에 대한 한 줄 설명. 모르는 폴더면 일반 안내.
    static func hint(for bucket: String) -> String {
        switch bucket {
        case "Library/Application Support":
            return "앱들이 실제 데이터를 넣어두는 곳입니다. iPhone 백업(MobileSync), 각종 앱의 저장 데이터가 여기 있습니다. "
                + "캐시가 아니라 데이터라서 이 앱은 건드리지 않습니다. 파인더로 열어 어떤 앱이 크게 쓰는지 확인해 보세요."
        case "Library/Developer":
            return "Xcode 와 시뮬레이터가 쓰는 곳입니다. CoreSimulator 기기, iOS 기기 지원 파일, DerivedData 가 여기 들어갑니다. "
                + "개발자 맥에서 가장 크게 부푸는 폴더입니다."
        case "Library/Caches":
            return "앱 캐시입니다. 이 앱이 정리 대상으로 다루는 곳입니다."
        case "Library/Containers":
            return "샌드박스 앱들의 데이터입니다. 캐시만 정리 대상이고 나머지는 앱 데이터입니다."
        case "Library/Group Containers":
            return "여러 앱이 공유하는 데이터입니다. 앱 데이터라 건드리지 않습니다."
        case "Pictures":
            return "사진 보관함입니다. 사진 앱에서 정리하세요."
        case "Downloads":
            return "다운로드 폴더입니다. 오래된 설치 파일은 이 앱이 정리 대상으로 다룹니다."
        case "Documents", "Desktop", "Movies", "Music":
            return "사용자 파일입니다. 이 앱은 절대 건드리지 않습니다."
        default:
            return "용량 차지 현황입니다. 이 앱은 이 폴더를 건드리지 않습니다."
        }
    }
}
