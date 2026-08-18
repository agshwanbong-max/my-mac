import Foundation

/// 사용자 홈을 기준으로 한 경로 해석기.
///
/// 테스트에서 임시 디렉터리를 홈처럼 주입할 수 있도록 홈 경로를 주입받는다.
/// 코어 전체에서 `FileManager.default.homeDirectoryForCurrentUser` 를 직접 부르는 곳은
/// `UserPaths.current()` 한 곳뿐이다.
public struct UserPaths: Sendable, Equatable {
    public let home: URL

    public init(home: URL) {
        self.home = home.standardizedFileURL
    }

    public static func current() -> UserPaths {
        UserPaths(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// 홈 상대 경로를 절대 URL 로 바꾼다. `/` 로 시작하면 절대 경로로 취급한다.
    public func resolve(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return home.appendingPathComponent(path).standardizedFileURL
    }

    /// 표시용으로 홈을 `~` 로 줄인다.
    public func abbreviate(_ url: URL) -> String {
        let full = url.standardizedFileURL.path
        let homePath = home.path
        if full == homePath { return "~" }
        if full.hasPrefix(homePath + "/") {
            return "~" + full.dropFirst(homePath.count)
        }
        return full
    }
}
