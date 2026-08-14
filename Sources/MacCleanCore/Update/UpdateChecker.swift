import Foundation

/// 새 버전이 나왔는지 확인한다.
///
/// App Store 밖에서 배포하면 업데이트를 알려줄 사람이 없다. 사용자는 첫 버전을 계속 쓰게 된다.
///
/// 일부러 **알림까지만** 한다. 앱 안에서 받아서 설치하는 건 하지 않는다.
/// 그러려면 프레임워크(Sparkle)를 번들에 끼워넣고 중첩 서명까지 맞춰야 하는데,
/// 그건 공증이 조용히 깨지기 쉬운 지점이다. 새 버전이 있다고 알려주고 브라우저를 여는 것만으로
/// "첫 버전에 갇히는" 문제는 해결된다.
public struct UpdateChecker: Sendable {

    /// 배포 서버에 올려두는 안내문.
    public struct Manifest: Codable, Sendable {
        public let version: String
        public let downloadURL: URL
        public let releaseNotesURL: URL?
        public let minimumSystemVersion: String?
        public let publishedAt: Date?

        public init(
            version: String,
            downloadURL: URL,
            releaseNotesURL: URL? = nil,
            minimumSystemVersion: String? = nil,
            publishedAt: Date? = nil
        ) {
            self.version = version
            self.downloadURL = downloadURL
            self.releaseNotesURL = releaseNotesURL
            self.minimumSystemVersion = minimumSystemVersion
            self.publishedAt = publishedAt
        }
    }

    public enum Result: Sendable {
        case upToDate
        case available(Manifest)
        /// 확인 자체를 못 했다. 네트워크가 없거나 서버가 응답하지 않는 경우.
        /// **조용히 넘어간다.** 업데이트 확인 실패로 사용자를 귀찮게 할 이유가 없다.
        case unavailable(String)
    }

    private let manifestURL: URL
    private let currentVersion: String
    private let session: URLSession

    public init(manifestURL: URL, currentVersion: String, session: URLSession = .shared) {
        self.manifestURL = manifestURL
        self.currentVersion = currentVersion
        self.session = session
    }

    public func check() async -> Result {
        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 10
        // 캐시된 안내문을 보면 새 버전이 나와도 모른다.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .unavailable(L("update.httpStatus", http.statusCode))
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(Manifest.self, from: data)

            return UpdateChecker.compare(current: currentVersion, manifest: manifest)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// 순수 비교. 네트워크 없이 테스트할 수 있게 떼어놨다.
    public static func compare(current: String, manifest: Manifest) -> Result {
        guard
            let currentVersion = AppVersion(current),
            let latest = AppVersion(manifest.version)
        else {
            return .unavailable(L("update.badVersionFormat"))
        }
        return latest > currentVersion ? .available(manifest) : .upToDate
    }
}
