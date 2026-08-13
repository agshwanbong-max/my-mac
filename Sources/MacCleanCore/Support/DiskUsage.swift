import Foundation

/// 디렉터리가 실제로 디스크에서 차지하는 크기를 잰다.
///
/// **논리 크기가 아니라 할당 크기(allocated size)를 쓴다.** 이유:
/// - APFS 는 파일을 복제(clone)하면 같은 블록을 공유한다. 논리 크기를 더하면 실제보다 크게 나온다.
/// - iCloud 최적화로 클라우드에만 있는 파일은 논리 크기는 크지만 로컬 점유는 0 이다.
/// - 스파스 파일도 마찬가지다.
///
/// 사용자에게 "이만큼 확보됩니다" 라고 말하려면 할당 크기가 맞다.
public struct DiskUsage: Sendable {

    public struct Measurement: Sendable {
        public var allocatedBytes: Int64
        public var fileCount: Int
        public var newestModification: Date?
        /// 순회 중 읽지 못한 항목이 있었는지 (권한 부족 등). 있으면 크기가 과소평가된 것이다.
        public var incomplete: Bool
    }

    /// 순회 상한. 이걸 넘으면 그만 세고 `incomplete = true` 로 표시한다.
    /// 노드 수백만 개짜리 폴더에서 UI 가 멈추는 걸 막는다.
    public static let nodeLimit = 400_000

    public init() {}

    /// 경로 하나의 실제 디스크 점유량을 잰다.
    /// - Parameter isCancelled: 주기적으로 물어보고 true 면 즉시 중단한다.
    public func measure(_ url: URL, isCancelled: () -> Bool = { false }) -> Measurement {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]

        var total: Int64 = 0
        var count = 0
        var newest: Date?
        var incomplete = false
        var visited = 0

        // 단일 파일이면 순회할 것도 없다.
        if let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true {
            let size = DiskUsage.allocatedSize(from: values)
            return Measurement(
                allocatedBytes: size,
                fileCount: 1,
                newestModification: values.contentModificationDate,
                incomplete: false
            )
        }

        // `enumerator(at:)` 는 디렉터리 심볼릭 링크를 따라가지 않는다 — 우리가 원하는 동작이다.
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in
                incomplete = true
                return true   // 하나 못 읽었다고 전체를 포기하지는 않는다
            }
        ) else {
            return Measurement(allocatedBytes: 0, fileCount: 0, newestModification: nil, incomplete: true)
        }

        for case let child as URL in enumerator {
            visited += 1
            if visited > DiskUsage.nodeLimit || isCancelled() {
                incomplete = true
                break
            }
            guard let values = try? child.resourceValues(forKeys: keys) else {
                incomplete = true
                continue
            }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { continue }

            total += DiskUsage.allocatedSize(from: values)
            count += 1
            if let modified = values.contentModificationDate {
                if newest == nil || modified > newest! { newest = modified }
            }
        }

        // 디렉터리 자신의 수정 시각도 후보에 넣는다.
        if let own = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            if newest == nil || own > newest! { newest = own }
        }

        return Measurement(
            allocatedBytes: total,
            fileCount: count,
            newestModification: newest,
            incomplete: incomplete
        )
    }

    private static func allocatedSize(from values: URLResourceValues) -> Int64 {
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let allocated = values.fileAllocatedSize { return Int64(allocated) }
        if let logical = values.fileSize { return Int64(logical) }
        return 0
    }
}
