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
        case .safe: return L("risk.safe")
        case .review: return L("risk.review")
        case .advisory: return L("risk.advisory")
        }
    }

    public var localizedExplanation: String {
        switch self {
        case .safe:
            return L("risk.safe.detail")
        case .review:
            return L("risk.review.detail")
        case .advisory:
            return L("risk.advisory.detail")
        }
    }
}
