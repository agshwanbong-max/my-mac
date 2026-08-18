import Foundation

/// 규칙이 대상을 어떤 단위로 쪼개는가.
public enum RuleMode: String, Codable, Sendable {
    /// 디렉터리의 1단계 자식 각각을 개별 후보로 만든다.
    /// 예: `~/Library/Caches/<앱별 폴더>` → 앱별로 선택할 수 있다.
    case eachChild

    /// 디렉터리 자체를 통째로 후보 하나로 만든다.
    /// 예: `~/.npm/_cacache`
    case wholeDirectory

    /// 디렉터리 안의 **파일만** 후보로 만든다. 하위 디렉터리는 건드리지 않는다.
    /// 예: `~/Library/Logs` 바로 아래의 `.log` 파일들
    case filesOnly
}

/// 데이터로 기술된 정리 규칙.
///
/// 규칙은 코드가 아니라 **데이터**다. 이게 중요한 이유:
/// - 규칙 전체를 한 화면에서 검토할 수 있다 (`RuleCatalog`)
/// - 테스트가 규칙을 한 줄씩 순회하며 불변식을 검사할 수 있다
/// - 규칙이 아무리 잘못 쓰여도 `PathGuard` 를 우회할 방법이 없다
public struct CleanupRule: Identifiable, Codable, Sendable {
    public let id: String

    /// 번역 키의 뿌리. 보통은 `id` 와 같다.
    ///
    /// 반복문으로 찍어내는 규칙들(앱마다 하나씩 만드는 캐시 규칙 같은 것)은
    /// 문구가 똑같고 앱 이름만 다르다. 그런 규칙은 키를 공유하고 이름만 인자로 넘긴다 —
    /// 같은 문장을 여섯 번 번역하게 만들 이유가 없다.
    public let textKey: String

    /// 문구의 `%@` 자리에 끼워 넣을 값. 없으면 서식 인자 없이 조회한다.
    public let textArgument: String?

    /// 화면에 나오는 규칙 이름.
    public var title: String { text("title") }

    /// 이게 뭔지에 대한 설명. UI 에 그대로 노출된다.
    public var explanation: String { text("explanation") }

    /// 지웠을 때 무슨 일이 벌어지는지. 애매하면 안 된다.
    public var consequence: String { text("consequence") }

    /// 규칙 문구는 `Localizable.strings` 에 `rule.<키>.<항목>` 으로 들어 있다.
    /// 그래서 규칙 목록은 순수한 구조로 남고, 번역자는 문구만 한 파일에서 검토할 수 있다.
    private func text(_ part: String) -> String {
        let key = "rule.\(textKey).\(part)"
        if let argument = textArgument { return L(key, argument) }
        return L(key)
    }

    public let category: FindingCategory
    public let risk: RiskLevel

    /// 홈 상대 경로. `/` 로 시작하면 절대 경로.
    public let path: String
    public let mode: RuleMode
    public let removal: RemovalMode

    /// 이 일수 이내에 수정된 항목은 건너뛴다. "지금 쓰고 있는 것"을 지우지 않기 위한 장치.
    public let minimumAgeDays: Int
    /// 이 크기 미만은 목록에 올리지 않는다. 목록이 잡음으로 차는 걸 막는다.
    public let minimumBytes: Int64

    /// 이 규칙 안에서도 예외적으로 건너뛸 자식 이름들.
    /// (캐시 폴더인 척하면서 실제 데이터를 담는 악명 높은 앱들)
    ///
    /// **접두사로 비교한다.** 앱들이 `Adobe Camera Raw 2` 처럼 버전 번호를 붙여
    /// 폴더 이름을 바꾸기 때문이다. 실제로 정확히 일치로 비교하다가
    /// `Adobe Camera Raw 2` 가 차단 목록을 그대로 빠져나간 적이 있다.
    public let deniedChildNames: Set<String>

    /// 지워도 되지만 **다시 만드는 비용이 큰** 자식들. 위험 등급을 `.review` 로 낮춘다.
    /// (수백 MB 재다운로드 같은 것들 — 지울지 말지는 사용자가 알고 결정해야 한다)
    /// 여기도 접두사로 비교한다.
    public let costlyChildNames: Set<String>

    /// 이 이름의 자식만 처리한다. 비어 있으면 전부.
    public let allowedChildNames: Set<String>

    /// 이 확장자를 가진 파일만 처리한다 (소문자, 점 없이). 비어 있으면 확장자를 따지지 않는다.
    /// 다운로드 폴더처럼 사용자 파일이 섞인 곳에서 대상을 좁히는 데 쓴다.
    public let allowedExtensions: Set<String>

    /// 전체 디스크 접근 권한이 있어야 읽히는 경로인가.
    public let requiresFullDiskAccess: Bool

    /// 이 규칙이 딸린 앱의 번들 ID. 그 앱이 실행 중이면 규칙을 건너뛴다.
    public let ownerBundleIdentifier: String?

    /// `.adviseOnly` 규칙에서 사용자에게 보여줄 복사용 명령어. 앱은 실행하지 않는다.
    public let suggestedCommand: String?

    public init(
        id: String,
        textKey: String? = nil,
        textArgument: String? = nil,
        category: FindingCategory,
        risk: RiskLevel,
        path: String,
        mode: RuleMode,
        removal: RemovalMode = .trashItem,
        minimumAgeDays: Int = 1,
        minimumBytes: Int64 = 1_000_000,
        deniedChildNames: Set<String> = [],
        costlyChildNames: Set<String> = [],
        allowedChildNames: Set<String> = [],
        allowedExtensions: Set<String> = [],
        requiresFullDiskAccess: Bool = false,
        ownerBundleIdentifier: String? = nil,
        suggestedCommand: String? = nil
    ) {
        self.id = id
        self.textKey = textKey ?? id
        self.textArgument = textArgument
        self.category = category
        self.risk = risk
        self.path = path
        self.mode = mode
        self.removal = removal
        self.minimumAgeDays = minimumAgeDays
        self.minimumBytes = minimumBytes
        self.deniedChildNames = deniedChildNames
        self.costlyChildNames = costlyChildNames
        self.allowedChildNames = allowedChildNames
        self.allowedExtensions = allowedExtensions
        self.requiresFullDiskAccess = requiresFullDiskAccess
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.suggestedCommand = suggestedCommand
    }

    /// 이 규칙이 만든 후보에 적용할 관문 제약.
    public func constraints(root: URL) -> RuleConstraints {
        let rootDepth = root.standardizedFileURL.pathComponents.count - 1
        // `eachChild` / `filesOnly` 는 루트보다 최소 한 단계 깊어야 한다.
        // `wholeDirectory` 는 루트 자신이 대상이므로 루트 깊이를 그대로 요구한다.
        let required = (mode == .wholeDirectory) ? rootDepth : rootDepth + 1
        return RuleConstraints(allowedRoots: [rootParentForGuard(root: root)], minimumDepth: required)
    }

    /// `wholeDirectory` 는 루트 자신이 대상이므로, 관문의 "허용 루트"는 그 부모여야 한다.
    private func rootParentForGuard(root: URL) -> URL {
        mode == .wholeDirectory ? root.deletingLastPathComponent() : root
    }
}
