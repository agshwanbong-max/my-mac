import CryptoKit
import Foundation

/// 파일 내용 해시.
///
/// 중복 판정에만 쓴다. 전체를 읽어야 하므로 비싸다 — 크기와 앞부분으로 후보를 좁힌 뒤
/// 마지막에만 부른다.
public enum FileHash {

    /// 한 번에 읽어들일 크기. 큰 파일을 통째로 메모리에 올리지 않기 위한 것.
    private static let chunkSize = 1 << 20   // 1MB

    /// SHA-256. 읽지 못하면 nil.
    ///
    /// - Parameter prefixBytes: 앞에서 이만큼만 읽는다. nil 이면 전체.
    ///   후보를 좁히는 1차 통과에서 쓴다 — 앞 4KB 만 봐도 대부분의 오답이 걸러진다.
    public static func sha256(of url: URL, prefixBytes: Int? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var remaining = prefixBytes

        while true {
            let wanted = remaining.map { min($0, chunkSize) } ?? chunkSize
            guard wanted > 0 else { break }
            guard let data = try? handle.read(upToCount: wanted), !data.isEmpty else { break }

            hasher.update(data: data)
            if let left = remaining {
                remaining = left - data.count
                if remaining! <= 0 { break }
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
