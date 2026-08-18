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
        maximumFolders: Int = 20,
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
            // 스캐너 단위 진행률만으로는 이 스캐너가 도는 20~30초 동안 화면이 멈춘 것처럼 보인다.
            // 파일 수를 흘려보내서 뭔가 돌아가고 있다는 걸 알린다.
            if visited % 20_000 == 0 {
                context.progress.note(L("progress.walkingHome", visited / 1000))
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
                message: L("warn.breakdownIncomplete")
            ))
        }

        // ── 시스템 데이터 합계 ─────────────────────────────────────────
        // macOS 저장 공간 화면의 "시스템 데이터" 숫자와 이어붙이기 위한 것.
        // 이게 없으면 "앱은 13GB 라는데 시스템 설정은 71GB 라니 뭐가 맞나" 가 된다.
        let systemDataTotal = folderTotals
            .filter { MacOSStorageCategory.forHomeBucket($0.key) == .systemData }
            .reduce(Int64(0)) { $0 + $1.value }

        if systemDataTotal > 0 {
            findings.append(Finding(
                id: "systemData.summary",
                ruleID: "advice.systemDataSummary",
                category: .systemData,
                risk: .advisory,
                title: L("breakdown.total.title"),
                detail: L("breakdown.total.detail"),
                consequence: L("breakdown.total.consequence"),
                path: nil,
                reclaimableBytes: systemDataTotal,
                itemCount: 0,
                lastModified: nil,
                removal: .adviseOnly
            ))
        }

        // ── 폴더별 합계 ────────────────────────────────────────────────
        let topFolders = folderTotals
            .sorted { $0.value > $1.value }
            .prefix(maximumFolders)

        for entry in topFolders {
            let url = home.appendingPathComponent(entry.key)
            let storageCategory = MacOSStorageCategory.forHomeBucket(entry.key)
            findings.append(Finding(
                id: "space.folder|\(entry.key)",
                ruleID: "advice.spaceBreakdown",
                // 시스템 데이터로 세어지는 건 전용 화면으로 보낸다.
                // 다른 폴더들과 섞여 있으면 macOS 숫자와 이어붙일 수가 없다.
                category: storageCategory == .systemData ? .systemData : .spaceBreakdown,
                risk: .advisory,
                title: "~/\(entry.key)",
                detail: L("breakdown.folder.detail", folderFileCounts[entry.key] ?? 0, storageCategory.localizedTitle),
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
                consequence: L("breakdown.largeFile.consequence"),
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
        let all = relative.split(separator: "/", omittingEmptySubsequences: true)

        // 마지막 요소는 파일 이름이다. 묶음은 **폴더**여야 하므로 떼어낸다.
        // 이걸 안 떼서 `~/Library/loose.txt` 가 "Library/loose.txt" 라는
        // 묶음이 되고 있었다 (테스트가 잡았다).
        let parts = all.dropLast()
        guard let first = parts.first else { return nil }   // 홈 바로 아래 파일

        if first == "Library", parts.count >= 2 {
            let second = String(parts[1])
            // 이 폴더들은 안에 앱별로 다시 나뉜다. 한 덩어리로 보여주면 의미가 없다.
            // 실제로 "Application Support 38GB" 라는 한 줄로는 아무것도 알 수 없었는데,
            // 한 단계 더 쪼개니 배경화면 13GB, Claude 13GB 가 바로 드러났다.
            if SpaceBreakdownScanner.splitDeeper.contains(second), parts.count >= 3 {
                return "Library/\(second)/\(parts[2])"
            }
            return "Library/\(second)"
        }
        return String(first)
    }

    /// 한 단계 더 쪼개서 보여줄 `~/Library` 하위 폴더들.
    static let splitDeeper: Set<String> = [
        "Application Support",
        "Developer",
        "Containers",
        "Group Containers",
    ]

    /// 그 폴더가 뭔지에 대한 한 줄 설명. 모르는 폴더면 일반 안내.
    static func hint(for bucket: String) -> String {
        switch bucket {
        case "Library/Application Support/com.apple.wallpaper":
            return L("breakdown.hint.wallpaper")
        case "Library/Application Support/Claude":
            return L("breakdown.hint.claude")
        case "Library/Application Support/Notion", "Library/Application Support/Slack",
             "Library/Application Support/Code":
            return L("breakdown.hint.electron")
        case "Library/Application Support/Google":
            return L("breakdown.hint.chrome")
        case "Library/Developer/Xcode":
            return L("breakdown.hint.developer")
        case "Library/Developer/CoreSimulator":
            return L("breakdown.hint.coreSimulator")
        case "Library/Application Support":
            return L("breakdown.hint.appSupport")
        case "Library/Developer":
            return L("breakdown.hint.xcodeShared")
        case "Library/Caches":
            return L("breakdown.hint.caches")
        case "Library/Containers":
            return L("breakdown.hint.containers")
        case "Library/Group Containers":
            return L("breakdown.hint.groupContainers")
        case "Pictures":
            return L("breakdown.hint.pictures")
        case "Downloads":
            return L("breakdown.hint.downloads")
        case "Documents", "Desktop", "Movies", "Music":
            return L("breakdown.hint.userFiles")
        default:
            return L("breakdown.hint.generic")
        }
    }
}
