import Foundation

/// 부팅 볼륨의 용량 현황.
public struct VolumeSnapshot: Codable, Sendable {
    public var totalCapacity: Int64
    /// 순수 여유 공간.
    public var availableCapacity: Int64
    /// macOS 가 "사용 가능"이라고 표시하는 값. 지울 수 있는(purgeable) 공간이 포함돼 있다.
    public var availableForImportantUsage: Int64
    /// Time Machine 로컬 스냅샷 개수.
    public var localSnapshotCount: Int

    /// 실제로는 비어 있지 않지만 시스템이 필요하면 회수할 수 있는 양.
    /// 이 값이 크다는 건 "지웠는데 용량이 안 늘어난다"는 증상의 원인이다.
    public var purgeableEstimate: Int64 {
        max(0, availableForImportantUsage - availableCapacity)
    }

    public init(
        totalCapacity: Int64,
        availableCapacity: Int64,
        availableForImportantUsage: Int64,
        localSnapshotCount: Int
    ) {
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.availableForImportantUsage = availableForImportantUsage
        self.localSnapshotCount = localSnapshotCount
    }

    public static let unknown = VolumeSnapshot(
        totalCapacity: 0,
        availableCapacity: 0,
        availableForImportantUsage: 0,
        localSnapshotCount: 0
    )
}

public struct VolumeProbe: Sendable {

    private let runner: ShellRunner

    public init(runner: ShellRunner = ShellRunner()) {
        self.runner = runner
    }

    public func snapshot(home: URL) -> VolumeSnapshot {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]

        var total: Int64 = 0
        var available: Int64 = 0
        var important: Int64 = 0

        if let values = try? home.resourceValues(forKeys: keys) {
            total = Int64(values.volumeTotalCapacity ?? 0)
            available = Int64(values.volumeAvailableCapacity ?? 0)
            important = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        return VolumeSnapshot(
            totalCapacity: total,
            availableCapacity: available,
            availableForImportantUsage: important,
            localSnapshotCount: localSnapshotNames().count
        )
    }

    /// `tmutil listlocalsnapshots /` 로 로컬 스냅샷 목록을 읽는다. 읽기 전용이다.
    ///
    /// 스냅샷은 두 종류가 나온다. **둘 다 공간을 잡는다.**
    /// - `com.apple.TimeMachine.…`  Time Machine 로컬 스냅샷
    /// - `com.apple.os.update-…`    macOS 업데이트 전후로 만들어지는 스냅샷.
    ///   특히 `MSUPrepareUpdate` 는 다운로드해서 준비하다 만 업데이트라 몇 GB 를 그냥 붙잡고 있다.
    ///
    /// 처음에는 Time Machine 것만 셌는데, 실제 기기에서 업데이트 스냅샷만 남아 있는 경우가 확인돼
    /// 둘 다 세도록 고쳤다.
    public func localSnapshotNames() -> [String] {
        guard let result = try? runner.run(
            executable: "/usr/bin/tmutil",
            arguments: ["listlocalsnapshots", "/"]
        ), result.succeeded else {
            return []
        }

        return result.standardOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine.") || $0.hasPrefix("com.apple.os.update-") }
    }

    /// 스냅샷을 종류별로 나눈다.
    public func classifiedSnapshots() -> (timeMachine: [String], osUpdate: [String]) {
        let all = localSnapshotNames()
        return (
            all.filter { $0.hasPrefix("com.apple.TimeMachine.") },
            all.filter { $0.hasPrefix("com.apple.os.update-") }
        )
    }
}

/// 바이트 수를 사람이 읽는 문자열로.
public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: bytes)
    }
}
