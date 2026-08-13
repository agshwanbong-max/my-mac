import Foundation

/// 홈 안의 대용량 파일을 찾아 **보여주기만** 한다.
///
/// 전부 `.advisory` 다. 사용자 파일이므로 이 앱은 절대 손대지 않는다.
/// "뭐가 용량을 먹고 있는지 모르겠다" 는 상황을 해결해주는 게 목적이다.
public struct LargeFileScanner: Scanner {

    public let identifier = "largeFiles"

    private let minimumBytes: Int64
    private let maximumResults: Int

    public init(minimumBytes: Int64 = 1_000_000_000, maximumResults: Int = 25) {
        self.minimumBytes = minimumBytes
        self.maximumResults = maximumResults
    }

    /// 훑지 않을 곳. 어차피 다른 스캐너가 다루거나, 내부 구조를 헤집을 이유가 없는 곳들.
    private static let skippedDirectoryNames: Set<String> = [
        "Library", "node_modules", ".git", ".Trash", "Applications",
    ]

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
            .contentModificationDateKey,
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: context.paths.home,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return ([], [])
        }

        var candidates: [(url: URL, size: Int64, modified: Date?)] = []
        var visited = 0

        for case let url as URL in enumerator {
            visited += 1
            if visited > DiskUsage.nodeLimit || isCancelled() { break }

            guard let values = try? url.resourceValues(forKeys: keys) else { continue }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            if values.isDirectory == true {
                let name = url.lastPathComponent
                // 패키지(.app, .photoslibrary 등)와 제외 목록은 통째로 건너뛴다.
                if values.isPackage == true || LargeFileScanner.skippedDirectoryNames.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let size: Int64
            if let total = values.totalFileAllocatedSize {
                size = Int64(total)
            } else if let allocated = values.fileAllocatedSize {
                size = Int64(allocated)
            } else if let logical = values.fileSize {
                size = Int64(logical)
            } else {
                size = 0
            }
            if size >= minimumBytes {
                candidates.append((url: url, size: size, modified: values.contentModificationDate))
            }
        }

        let top = candidates.sorted { $0.size > $1.size }.prefix(maximumResults)

        let findings = top.map { candidate -> Finding in
            Finding(
                id: "largeFile|\(candidate.url.path)",
                ruleID: "advice.largeFiles",
                category: .largeFiles,
                risk: .advisory,
                title: candidate.url.lastPathComponent,
                detail: context.paths.abbreviate(candidate.url.deletingLastPathComponent()),
                consequence: "사용자 파일이라 이 앱은 건드리지 않습니다. 파인더에서 직접 확인하고 판단하세요.",
                path: candidate.url,
                reclaimableBytes: candidate.size,
                itemCount: 1,
                lastModified: candidate.modified,
                removal: .adviseOnly
            )
        }

        return (Array(findings), [])
    }
}
