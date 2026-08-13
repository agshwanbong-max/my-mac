import Foundation

public struct GuardDecision: Sendable, Equatable {
    public let allowed: Bool
    /// 거부된 이유. 로그와 UI 에 그대로 노출된다 — 왜 안 지웠는지 사용자가 알 수 있어야 한다.
    public let reason: String
    /// 어느 게이트에서 걸렸는지 (G1~G7).
    public let gate: String

    public static func allow() -> GuardDecision {
        GuardDecision(allowed: true, reason: "통과", gate: "-")
    }

    public static func deny(_ gate: String, _ reason: String) -> GuardDecision {
        GuardDecision(allowed: false, reason: reason, gate: gate)
    }
}

/// 삭제 후보 경로가 통과해야 하는 관문.
///
/// 스캔 때 한 번, **실행 직전에 한 번 더** 호출된다.
/// 두 번 부르는 이유: 스캔과 실행 사이에 파일이 바뀌거나, 경로가 심볼릭 링크로 바뀌치기 될 수 있다.
// `FileManager` 는 Sendable 이 아니지만, 여기서 쓰는 건 읽기 전용 조회뿐이고
// 스레드 안전하다. 그래서 `@unchecked` 로 명시한다.
public struct PathGuard: @unchecked Sendable {

    private let paths: UserPaths
    private let protected: ProtectedPaths
    private let fileManager: FileManager

    /// 홈이 놓인 볼륨의 device id. 다른 볼륨으로 넘어가는 걸 막는 데 쓴다.
    private let homeDeviceID: dev_t?

    public init(paths: UserPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.protected = ProtectedPaths(paths: paths)
        self.fileManager = fileManager

        var st = stat()
        if lstat(paths.home.path, &st) == 0 {
            self.homeDeviceID = st.st_dev
        } else {
            self.homeDeviceID = nil
        }
    }

    /// SIP 보호 플래그. `sys/stat.h` 의 `SF_RESTRICTED`.
    private static let sfRestricted: UInt32 = 0x0008_0000
    /// 사용자 잠금(`chflags uchg`) / 시스템 잠금.
    private static let ufImmutable: UInt32 = 0x0000_0002
    private static let sfImmutable: UInt32 = 0x0002_0000

    /// 경로 하나를 검사한다.
    ///
    /// - Parameters:
    ///   - url: 검사할 경로
    ///   - constraints: 이 경로를 제안한 규칙의 제약. 최소 깊이·루트 허용 범위를 여기서 가져온다.
    public func evaluate(_ url: URL, constraints: RuleConstraints) -> GuardDecision {
        let target = url.standardizedFileURL
        let path = target.path

        // ── G1. 형태 검사 ────────────────────────────────────────────────
        guard target.isFileURL, path.hasPrefix("/") else {
            return .deny("G1", "절대 파일 경로가 아님")
        }
        if path.contains("..") {
            return .deny("G1", "상위 경로 참조(..) 포함")
        }
        if path == "/" {
            return .deny("G1", "볼륨 루트")
        }

        // ── G2. 존재 · 심볼릭 링크 ──────────────────────────────────────
        var lst = stat()
        guard lstat(path, &lst) == 0 else {
            return .deny("G2", "경로가 존재하지 않음")
        }
        // `S_IFMT` 계열 상수는 Swift 로 넘어올 때 정수 타입이 애매해서 쓰지 않는다.
        // `lstat` 이 성공한 경로에 대해 Foundation 으로 링크 여부를 묻는다.
        let linkCheck = try? target.resourceValues(forKeys: [.isSymbolicLinkKey])
        if linkCheck?.isSymbolicLink == true {
            // 링크 자체는 지워도 무해하지만, 링크를 따라 엉뚱한 곳을 지우는 사고를 원천 차단한다.
            return .deny("G2", "심볼릭 링크 — 링크는 대상으로 삼지 않음")
        }

        // 링크를 해석한 실제 경로도 같은 검사를 통과해야 한다 (경로 바꿔치기 방어).
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        if resolved.path != path {
            if let hit = protected.matchedDenyRule(for: resolved) {
                return .deny("G2", "링크 해석 결과가 보호 경로: \(hit)")
            }
        }

        // ── G3. 보호 경로 (덮어쓸 수 없는 거부 목록) ───────────────────
        //
        // 순서가 중요하다. 예외로 **못 여는** 차단부터 본다.
        // 이 둘을 한 검사로 합쳐두면, 접두사에 먼저 걸린 경로가 예외로 통과하면서
        // 이름 기반 차단(.git 등)을 건너뛰게 된다. 실제로 그 구멍이 있었다.
        if let hit = protected.matchedUnwaivableRule(for: target) {
            return .deny("G3", "보호 대상: \(hit)")
        }

        // 접두사 차단. 규칙이 명시한 예외 **하나만** 열 수 있다.
        // 여러 접두사에 걸렸다면 그 전부가 예외여야 통과한다.
        let prefixHits = protected.matchedPrefixRules(for: target)
        if !prefixHits.isEmpty {
            let exempt = constraints.exemptProtectedPrefix?.standardizedFileURL.path
            if let blocked = prefixHits.first(where: { $0 != exempt }) {
                return .deny("G3", "보호 경로: \(blocked)")
            }
        }

        // ── G4. 허용 루트 안에 있는가 ───────────────────────────────────
        var insideAllowedRoot = false
        for root in constraints.allowedRoots {
            let rootPath = root.standardizedFileURL.path
            if path.hasPrefix(rootPath + "/") {
                insideAllowedRoot = true
                break
            }
        }
        if !insideAllowedRoot {
            return .deny("G4", "규칙이 허용한 루트 밖")
        }

        // 홈이나 볼륨 루트 자체, 혹은 그 직계 조상은 절대 안 된다.
        if path == paths.home.path {
            return .deny("G4", "홈 디렉터리 자체")
        }
        if paths.home.path.hasPrefix(path + "/") {
            return .deny("G4", "홈 디렉터리의 상위 경로")
        }

        // ── G5. 깊이 ────────────────────────────────────────────────────
        // 컴포넌트 수가 얕을수록 파괴력이 크다. 규칙마다 최소 깊이를 요구한다.
        let depth = target.pathComponents.count - 1   // 맨 앞 "/" 제외
        if depth < constraints.minimumDepth {
            return .deny("G5", "경로 깊이 \(depth) < 최소 \(constraints.minimumDepth)")
        }

        // ── G6. 소유권 · 볼륨 · 잠금 플래그 ─────────────────────────────
        if lst.st_uid != getuid() {
            return .deny("G6", "현재 사용자 소유가 아님 (uid \(lst.st_uid))")
        }
        if let homeDevice = homeDeviceID, lst.st_dev != homeDevice, !constraints.allowsOtherVolumes {
            return .deny("G6", "홈과 다른 볼륨")
        }
        if lst.st_flags & PathGuard.sfRestricted != 0 {
            return .deny("G6", "SIP 보호 플래그(SF_RESTRICTED)")
        }
        if lst.st_flags & (PathGuard.ufImmutable | PathGuard.sfImmutable) != 0 {
            return .deny("G6", "잠금 플래그(immutable)")
        }

        // ── G7. 쓰기 권한 ───────────────────────────────────────────────
        // 부모 디렉터리에 쓰기 권한이 없으면 어차피 실패한다. 미리 걸러 실행 단계를 깨끗하게 유지한다.
        let parent = target.deletingLastPathComponent().path
        if !fileManager.isWritableFile(atPath: parent) {
            return .deny("G7", "상위 디렉터리에 쓰기 권한 없음")
        }

        return .allow()
    }
}

/// `PathGuard` 가 규칙에게서 필요로 하는 최소 정보.
///
/// `CleanupRule` 전체를 넘기지 않고 이 작은 구조체만 넘기는 이유는,
/// 전용 스캐너(시뮬레이터·node_modules 등)도 같은 관문을 쓸 수 있게 하기 위해서다.
///
/// `Codable` 인 이유는 `Finding` 에 그대로 실려 가기 때문이다.
/// 스캔할 때 쓴 제약과 **실행 직전에 다시 검사할 때 쓰는 제약이 반드시 같아야** 하고,
/// 같은 값을 들고 다니는 게 그걸 보장하는 가장 단순한 방법이다.
public struct RuleConstraints: Sendable, Codable, Hashable {
    public let allowedRoots: [URL]
    public let minimumDepth: Int
    public let allowsOtherVolumes: Bool

    /// 보호 경로 목록(G3)에서 **이 접두사 하나만** 예외로 연다.
    ///
    /// iOS 백업처럼 "기본적으로는 보호하지만 사용자가 명시적으로 고르면 지울 수 있어야 하는" 항목을 위한 장치다.
    /// 중요한 점: 예외는 G3 의 경로 접두사 판정에만 적용되고,
    /// **이름 기반 차단·번들 차단·나머지 게이트(G1·G2·G4~G7)는 그대로 전부 적용된다.**
    public let exemptProtectedPrefix: URL?

    public init(
        allowedRoots: [URL],
        minimumDepth: Int,
        allowsOtherVolumes: Bool = false,
        exemptProtectedPrefix: URL? = nil
    ) {
        self.allowedRoots = allowedRoots
        self.minimumDepth = minimumDepth
        self.allowsOtherVolumes = allowsOtherVolumes
        self.exemptProtectedPrefix = exemptProtectedPrefix
    }
}
