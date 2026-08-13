import Foundation

/// 정리 후보의 위험 등급.
///
/// 이 앱의 안전 정책은 전부 이 세 등급 위에 세워져 있다.
/// - `.safe`     지워도 시스템/앱이 알아서 다시 만든다.
/// - `.review`   지우면 재다운로드·재빌드가 필요하거나, 유일본일 수 있다. 항목별 승인 필수.
/// - `.advisory` **앱이 절대 건드리지 않는다.** 무엇이 용량을 먹는지 알려주고 방법만 안내한다.
public enum RiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case safe
    case review
    case advisory

    public var rank: Int {
        switch self {
        case .safe: return 0
        case .review: return 1
        case .advisory: return 2
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    /// 앱이 스스로 파일을 옮기거나 지워도 되는 등급인가.
    public var appMayRemove: Bool {
        self != .advisory
    }

    /// 스캔 직후 체크박스를 기본으로 켜둬도 되는 등급인가.
    /// 보수적 정책이므로 `.safe` 만 기본 선택되고, 그마저도 실행 전 확인 창을 거친다.
    public var defaultsToSelected: Bool {
        self == .safe
    }

    public var localizedTitle: String {
        switch self {
        case .safe: return "안전"
        case .review: return "확인 필요"
        case .advisory: return "안내 전용"
        }
    }

    public var localizedExplanation: String {
        switch self {
        case .safe:
            return "지워도 시스템이나 앱이 자동으로 다시 만드는 캐시·로그입니다. 그래도 실행 전 승인을 받습니다."
        case .review:
            return "지우면 다시 받거나 다시 빌드해야 합니다. 유일본일 수도 있어 항목마다 직접 선택해야 합니다."
        case .advisory:
            return "이 앱은 이 항목을 건드리지 않습니다. 용량을 차지하는 이유와 직접 처리하는 방법만 알려줍니다."
        }
    }
}
