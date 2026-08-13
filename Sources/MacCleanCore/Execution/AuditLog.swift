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

    /// 기록 하나를 남긴다. 되돌리기도 여기에 남는다.
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

    /// 이번 달 기록을 새 것부터 읽는다.
    public func recentEntries(limit: Int = 200) -> [Entry] {
        decode(fileURL: currentFileURL).suffix(limit).reversed()
    }

    /// 남아 있는 **모든 달**의 기록을 새 것부터 읽는다.
    ///
    /// 되돌리기에 필요하다. 지난달에 지운 걸 이번 달에 되돌리는 건 흔한 일인데,
    /// 이번 달 파일만 보면 그게 아예 안 보인다.
    public func allEntries(limit: Int = 500) -> [Entry] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let logs = files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // 파일 이름이 곧 연월이라 이대로 정렬된다

        var entries: [Entry] = []
        for log in logs {
            entries.append(contentsOf: decode(fileURL: log).reversed())
            if entries.count >= limit { break }
        }
        return Array(entries.prefix(limit))
    }

    private func decode(fileURL: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entries: [Entry] = []
        for line in data.split(separator: 0x0A) {
            if let entry = try? decoder.decode(Entry.self, from: Data(line)) {
                entries.append(entry)
            }
        }
        return entries
    }
}
