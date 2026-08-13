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
    public let title: String

    /// 이게 뭔지에 대한 설명. UI 에 그대로 노출된다.
    public let explanation: String
    /// 지웠을 때 무슨 일이 벌어지는지. 애매하면 안 된다.
    public let consequence: String

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
    public let deniedChildNames: Set<String>

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
        title: String,
        explanation: String,
        consequence: String,
        category: FindingCategory,
        risk: RiskLevel,
        path: String,
        mode: RuleMode,
        removal: RemovalMode = .trashItem,
        minimumAgeDays: Int = 1,
        minimumBytes: Int64 = 1_000_000,
        deniedChildNames: Set<String> = [],
        allowedChildNames: Set<String> = [],
        allowedExtensions: Set<String> = [],
        requiresFullDiskAccess: Bool = false,
        ownerBundleIdentifier: String? = nil,
        suggestedCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.consequence = consequence
        self.category = category
        self.risk = risk
        self.path = path
        self.mode = mode
        self.removal = removal
        self.minimumAgeDays = minimumAgeDays
        self.minimumBytes = minimumBytes
        self.deniedChildNames = deniedChildNames
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
