import Foundation

/// **이거 지워도 되나?** 에 대한 한 줄 대답.
///
/// 이 타입이 이 기능의 전부다. 나머지(중요도·복구 가능성·근거)는 전부 이 판정을 뒷받침하려고 있다.
///
/// 처음에는 "이건 캐시입니다", "이건 사용자 파일입니다" 같은 설명만 보여줬는데,
/// 정작 사용자는 "그래서 지워도 된다는 거야 말라는 거야" 를 알 수 없었다.
/// 설명은 판단의 재료지 판단이 아니다. 그래서 결론을 맨 앞에 놓는다.
public enum DeletionVerdict: String, Codable, Sendable, CaseIterable {

    /// 지워도 된다. 잃는 게 없거나, 알아서 다시 생긴다.
    case safe

    /// 지울 수는 있는데 대가가 있다. 무슨 대가인지 알고 결정해야 한다.
    case checkFirst

    /// 지우지 마라. 되돌릴 방법이 없다.
    case keep

    public var localizedTitle: String {
        switch self {
        case .safe: return L("verdict.safe.title")
        case .checkFirst: return L("verdict.checkFirst.title")
        case .keep: return L("verdict.keep.title")
        }
    }

    /// 목록에 붙는 아주 짧은 딱지.
    public var shortLabel: String {
        switch self {
        case .safe: return L("verdict.safe.short")
        case .checkFirst: return L("verdict.checkFirst.short")
        case .keep: return L("verdict.keep.short")
        }
    }
}

/// 얼마나 소중한가. 판정을 만들어내는 두 축 중 하나.
public enum ImportanceLevel: Int, Codable, Sendable, CaseIterable, Comparable {

    /// 버려도 된다. 시스템이나 앱이 알아서 다시 만든다.
    case disposable = 0

    /// 다시 구할 수 있다. 재다운로드·재빌드·재설치가 필요할 뿐이다.
    case replaceable = 1

    /// 직접 만든 것으로 보인다. 잃으면 다시 만들어야 한다.
    case personal = 2

    /// 자격 증명이나 유일본. 잃으면 되돌릴 방법이 없다.
    case critical = 3

    public static func < (lhs: ImportanceLevel, rhs: ImportanceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var localizedTitle: String {
        switch self {
        case .disposable: return L("importance.disposable")
        case .replaceable: return L("importance.replaceable")
        case .personal: return L("importance.personal")
        case .critical: return L("importance.critical")
        }
    }
}

/// 사라졌을 때 되찾을 수 있는가. 판정을 만들어내는 나머지 한 축.
///
/// 중요도와 **별개의 축**인 게 중요하다.
/// 소중한 파일이라도 클라우드에 같은 게 있으면 로컬 사본은 지워도 된다.
/// 반대로 별것 아닌 파일이라도 그게 세상에 하나뿐이면 함부로 못 지운다.
/// 이 둘을 한 숫자로 뭉개면 어느 쪽도 제대로 말할 수 없다.
public enum Recoverability: String, Codable, Sendable, CaseIterable {
    case regenerates        // 시스템·앱이 자동으로 다시 만든다
    case redownloadable     // 인터넷에서 다시 받을 수 있다
    case syncedElsewhere    // 클라우드에 같은 것이 있다
    case inVersionControl   // 원격 저장소에 올라가 있다
    case unknown            // 판단할 근거를 못 찾았다
    case onlyCopy           // 여기에만 있는 것으로 보인다

    public var localizedTitle: String {
        switch self {
        case .regenerates: return L("recoverability.regenerates")
        case .redownloadable: return L("recoverability.redownloadable")
        case .syncedElsewhere: return L("recoverability.syncedElsewhere")
        case .inVersionControl: return L("recoverability.inVersionControl")
        case .unknown: return L("recoverability.unknown")
        case .onlyCopy: return L("recoverability.onlyCopy")
        }
    }
}

/// 판정의 근거 하나.
///
/// 근거를 항상 같이 보여주는 이유: 점수만 던지면 사용자가 믿을 수도, 반박할 수도 없다.
/// "왜 그렇게 판단했는지" 가 보여야 사용자가 앱의 판단이 틀린 경우를 잡아낼 수 있다.
public struct ImportanceSignal: Codable, Sendable, Hashable, Identifiable {
    public enum Direction: String, Codable, Sendable {
        case raises   // 더 소중하다는 근거
        case lowers   // 덜 소중하다는 근거
        case context  // 판단에 참고한 사실
    }

    public var id: String { title }
    public let direction: Direction
    public let title: String
    public let detail: String

    public init(direction: Direction, title: String, detail: String) {
        self.direction = direction
        self.title = title
        self.detail = detail
    }
}

/// 경로 하나에 대한 판단 결과.
public struct ImportanceAssessment: Codable, Sendable, Hashable {

    /// **결론.** 사용자가 제일 먼저 보는 것.
    public let verdict: DeletionVerdict

    /// 결론에 붙는 한 줄 이유. 예: "다음 빌드 때 다시 만들어집니다"
    public let headline: String

    /// 지웠을 때 치르는 대가. 없으면 "없음".
    /// 예: "2.3GB 를 다시 내려받아야 합니다"
    public let cost: String

    public let level: ImportanceLevel
    public let recoverability: Recoverability

    /// 이 판단의 근거. UI 에서는 접어둔다.
    public let signals: [ImportanceSignal]

    public init(
        verdict: DeletionVerdict,
        headline: String,
        cost: String,
        level: ImportanceLevel,
        recoverability: Recoverability,
        signals: [ImportanceSignal]
    ) {
        self.verdict = verdict
        self.headline = headline
        self.cost = cost
        self.level = level
        self.recoverability = recoverability
        self.signals = signals
    }
}
