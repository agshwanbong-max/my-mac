import Foundation

/// 정리 후보 하나를 어떻게 없앨 것인가.
public enum RemovalMode: String, Codable, Sendable {
    /// 기본값. 항목을 **휴지통으로 이동**한다. 실수해도 되돌릴 수 있다.
    case trashItem

    /// 되돌릴 수 없는 완전 삭제.
    /// "휴지통 비우기"처럼 본질적으로 영구인 작업에만 붙는다. 규칙에서 명시적으로 요청해야 한다.
    case permanentDelete

    /// 앱이 파일을 만지지 않는다. 설명과 (필요하면) 사용자가 직접 실행할 명령어만 제공한다.
    case adviseOnly

    /// 허용 목록에 등록된 도구 명령으로 처리한다. (예: `xcrun simctl delete <UDID>`)
    /// 임의의 셸 명령은 실행할 수 없다 — `ToolCommand.allowed` 참고.
    case toolCommand

    public var localizedTitle: String {
        switch self {
        case .trashItem: return "휴지통으로 이동"
        case .permanentDelete: return "완전 삭제 (복구 불가)"
        case .adviseOnly: return "안내만"
        case .toolCommand: return "전용 도구로 삭제"
        }
    }

    public var isReversible: Bool {
        self == .trashItem
    }
}

/// 앱이 실행해도 되는, 미리 정해진 도구 명령.
///
/// 임의 문자열을 셸에 넘기지 않는다. 실행 파일과 첫 인자 조합이 허용 목록에 있어야만 통과한다.
public struct ToolCommand: Codable, Sendable, Hashable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// 삭제 목적으로 실행이 허용된 조합. 여기 없으면 실행되지 않는다.
    /// (`sudo` 가 필요한 명령은 의도적으로 하나도 없다.)
    public static let allowedPrefixes: [[String]] = [
        ["/usr/bin/xcrun", "simctl", "delete"],
    ]

    public var isAllowed: Bool {
        for prefix in ToolCommand.allowedPrefixes {
            guard prefix.count >= 1 else { continue }
            guard executable == prefix[0] else { continue }
            let needed = Array(prefix.dropFirst())
            guard arguments.count >= needed.count else { continue }
            if Array(arguments.prefix(needed.count)) == needed {
                return true
            }
        }
        return false
    }

    public var displayString: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

/// 스캔이 찾아낸 정리 후보 하나.
public struct Finding: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var ruleID: String
    public var category: FindingCategory
    public var risk: RiskLevel

    public var title: String
    /// 이게 무엇이고 왜 여기 떴는지에 대한 한 줄 설명.
    public var detail: String
    /// 지웠을 때 무슨 일이 벌어지는가. (예: "다음 빌드 때 다시 만들어집니다 — 첫 빌드가 느려집니다")
    public var consequence: String

    /// 대상 경로. 안내 전용 항목은 경로가 없을 수 있다.
    public var path: URL?

    /// 실제로 디스크에서 회수되는 바이트 수 (allocated size 기준).
    public var reclaimableBytes: Int64
    /// 포함된 파일 개수 (표시용).
    public var itemCount: Int
    /// 마지막 수정 시각. 실행 직전 재검증에 쓰인다.
    public var lastModified: Date?

    public var removal: RemovalMode
    /// `.toolCommand` 일 때 실행할 명령.
    public var toolCommand: ToolCommand?
    /// `.adviseOnly` 일 때 사용자에게 보여줄 복사용 명령어. 앱은 실행하지 않는다.
    public var suggestedCommand: String?

    /// 이 후보를 만들어낼 때 통과시킨 관문 제약.
    /// 실행 직전 재검사에서 **똑같은 제약**으로 다시 검사하기 위해 들고 다닌다.
    /// 없으면 실행기가 삭제를 거부한다 (안내 전용 항목은 애초에 실행 대상이 아니다).
    public var constraints: RuleConstraints?

    public init(
        id: String,
        ruleID: String,
        category: FindingCategory,
        risk: RiskLevel,
        title: String,
        detail: String,
        consequence: String,
        path: URL?,
        reclaimableBytes: Int64,
        itemCount: Int,
        lastModified: Date?,
        removal: RemovalMode,
        toolCommand: ToolCommand? = nil,
        suggestedCommand: String? = nil,
        constraints: RuleConstraints? = nil
    ) {
        self.id = id
        self.ruleID = ruleID
        self.category = category
        self.risk = risk
        self.title = title
        self.detail = detail
        self.consequence = consequence
        self.path = path
        self.reclaimableBytes = reclaimableBytes
        self.itemCount = itemCount
        self.lastModified = lastModified
        self.removal = removal
        self.toolCommand = toolCommand
        self.suggestedCommand = suggestedCommand
        self.constraints = constraints
    }

    /// 사용자가 선택할 수 있는 항목인가. 안내 전용은 선택 자체가 불가능하다.
    public var isSelectable: Bool {
        risk.appMayRemove && removal != .adviseOnly
    }
}
