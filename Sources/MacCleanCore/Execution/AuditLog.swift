import Foundation

/// 이 앱이 한 모든 일의 기록.
///
/// 한 줄에 JSON 하나(JSONL). 이유:
/// - 실행 중 앱이 죽어도 그때까지의 기록이 남는다
/// - `grep` / `jq` 로 바로 볼 수 있다
/// - 되돌리기가 필요할 때 "무엇이 휴지통 어디로 갔는지" 추적할 수 있다
///
/// 저장 위치: `~/Library/Application Support/MacClean/audit-YYYY-MM.jsonl`
public struct AuditLog: @unchecked Sendable {   // FileManager 보관 — PathGuard 의 설명 참고

    public struct Entry: Codable, Sendable {
        public let timestamp: Date
        public let action: String
        public let ruleID: String
        public let path: String?
        public let bytes: Int64
        public let removal: String
        /// 휴지통으로 옮겨진 뒤의 위치. 되돌릴 때 쓴다.
        public let trashedTo: String?
        public let succeeded: Bool
        public let message: String?
    }

    private let directory: URL
    private let fileManager: FileManager

    public init(paths: UserPaths, fileManager: FileManager = .default) {
        self.directory = paths.resolve("Library/Application Support/MacClean")
        self.fileManager = fileManager
    }

    public var currentFileURL: URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return directory.appendingPathComponent("audit-\(formatter.string(from: Date())).jsonl")
    }

    public func append(_ entry: Entry) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(entry)
            data.append(0x0A)   // 개행

            let url = currentFileURL
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // 기록 실패가 정리 작업 자체를 막아서는 안 된다. 조용히 넘어간다.
        }
    }

    /// 최근 기록을 새 것부터 읽는다.
    public func recentEntries(limit: Int = 200) -> [Entry] {
        guard let data = try? Data(contentsOf: currentFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let lines = data.split(separator: 0x0A)
        var entries: [Entry] = []
        for line in lines.suffix(limit) {
            if let entry = try? decoder.decode(Entry.self, from: Data(line)) {
                entries.append(entry)
            }
        }
        return entries.reversed()
    }
}
