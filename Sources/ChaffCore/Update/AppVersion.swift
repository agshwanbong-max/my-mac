import Foundation

/// `1.2.3` 형태의 버전. 비교만 할 수 있으면 된다.
///
/// 직접 만든 이유: 자동 업데이트를 위해 필요한 게 "이게 저것보다 새 버전인가" 하나뿐인데,
/// 그걸 위해 의존성을 들이는 건 과하다.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ text: String) {
        // "v1.2.3" 이나 "1.2.3-beta" 처럼 앞뒤에 뭐가 붙어도 숫자만 뽑아낸다.
        let trimmed = text.trimmingCharacters(in: .whitespaces)
            .drop(while: { !$0.isNumber })
            .prefix(while: { $0.isNumber || $0 == "." })

        let parts = trimmed.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.components = parts
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        // 자릿수가 다르면 짧은 쪽을 0 으로 채워 비교한다. 1.2 는 1.2.0 과 같다.
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
