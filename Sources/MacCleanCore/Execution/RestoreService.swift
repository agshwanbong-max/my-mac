import Foundation

/// 휴지통으로 보낸 것을 원래 자리로 되돌린다.
///
/// 이 앱은 처음부터 "되돌릴 수 있게" 를 원칙으로 삼았고, 그래서 기본 처리가 휴지통 이동이다.
/// 그런데 정작 되돌리는 건 사용자가 파인더에서 손으로 해야 했다.
/// 항목이 수십 개면 어느 게 이 앱이 옮긴 것인지도 알 수 없다.
///
/// 감사 로그에 이미 필요한 게 다 들어 있다 — 원래 경로와 휴지통 안의 위치.
/// 그걸 읽어서 되돌리기만 하면 된다.
public struct RestoreService: Sendable {

    /// 되돌릴 수 있는 항목 하나.
    public struct Entry: Identifiable, Sendable {
        public var id: String { trashedTo.path }
        /// 원래 있던 자리.
        public let originalPath: URL
        /// 지금 휴지통 안의 위치.
        public let trashedTo: URL
        public let bytes: Int64
        public let removedAt: Date
        public let ruleID: String

        /// 지금 되돌릴 수 있는가.
        public let isRestorable: Bool
        /// 안 되는 이유.
        public let blockedReason: String?
    }

    public enum Outcome: Sendable {
        case restored(to: URL)
        case failed(String)
    }

    private let paths: UserPaths
    private let audit: AuditLog
    private let fileManager: FileManager

    public init(paths: UserPaths, audit: AuditLog? = nil, fileManager: FileManager = .default) {
        self.paths = paths
        self.audit = audit ?? AuditLog(paths: paths)
        self.fileManager = fileManager
    }

    /// 되돌릴 수 있는 것들을 최근 순으로.
    public func restorable(limit: Int = 200) -> [Entry] {
        audit.allEntries(limit: limit)
            .filter { $0.action == "trash" && $0.succeeded }
            .compactMap { entry -> Entry? in
                guard
                    let originalPath = entry.path.map({ URL(fileURLWithPath: $0) }),
                    let trashedPath = entry.trashedTo.map({ URL(fileURLWithPath: $0) })
                else { return nil }

                var blocked: String?
                if !fileManager.fileExists(atPath: trashedPath.path) {
                    blocked = L("restore.blocked.gone")
                } else if fileManager.fileExists(atPath: originalPath.path) {
                    blocked = L("restore.blocked.occupied")
                }

                return Entry(
                    originalPath: originalPath,
                    trashedTo: trashedPath,
                    bytes: entry.bytes,
                    removedAt: entry.timestamp,
                    ruleID: entry.ruleID,
                    isRestorable: blocked == nil,
                    blockedReason: blocked
                )
            }
    }

    /// 한 항목을 원래 자리로 옮긴다.
    ///
    /// **덮어쓰지 않는다.** 원래 자리에 뭔가 있으면 아무것도 하지 않는다.
    /// 되돌리기가 새로운 데이터 손실을 만들면 안 된다.
    @discardableResult
    public func restore(_ entry: Entry) -> Outcome {
        guard fileManager.fileExists(atPath: entry.trashedTo.path) else {
            return .failed(L("restore.failed.gone"))
        }
        guard !fileManager.fileExists(atPath: entry.originalPath.path) else {
            return .failed(L("restore.failed.occupied"))
        }

        // 원래 있던 폴더가 그새 없어졌을 수 있다. 그럼 다시 만든다.
        let parent = entry.originalPath.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                return .failed(L("restore.failed.mkdir", error.localizedDescription))
            }
        }

        do {
            try fileManager.moveItem(at: entry.trashedTo, to: entry.originalPath)
        } catch {
            return .failed(L("restore.failed.generic", error.localizedDescription))
        }

        audit.append(AuditLog.Entry(
            timestamp: Date(),
            action: "restore",
            ruleID: entry.ruleID,
            path: entry.originalPath.path,
            bytes: entry.bytes,
            removal: RemovalMode.trashItem.rawValue,
            trashedTo: nil,
            succeeded: true,
            message: L("restore.audit.message")
        ))

        return .restored(to: entry.originalPath)
    }
}
