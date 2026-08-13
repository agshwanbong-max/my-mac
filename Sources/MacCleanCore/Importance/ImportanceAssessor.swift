import Foundation

/// 경로 하나를 보고 **지워도 되는지** 판단한다.
///
/// 설계 규칙 두 가지.
/// 1. **빠를 것.** 폴더 안을 재귀로 훑지 않는다. 목록에서 항목을 펼칠 때마다 불리기 때문이다.
/// 2. **근거를 남길 것.** 판정만 던지면 사용자가 믿을 수도 반박할 수도 없다.
///
/// 쓰는 신호는 전부 값싸게 얻을 수 있는 것들이다 — 경로, 확장자, 확장 속성, git 설정 파일, 접근 시각.
/// 파일 내용을 읽거나 해시하지 않는다.
public struct ImportanceAssessor: Sendable {

    private let paths: UserPaths

    public init(paths: UserPaths) {
        self.paths = paths
    }

    // MARK: - 분류표

    /// 직접 만드는 것들. 잃으면 같은 걸 다시 못 만든다.
    static let authoredExtensions: Set<String> = [
        "psd", "ai", "sketch", "fig", "xd", "afdesign", "afphoto",
        "pages", "numbers", "key", "docx", "xlsx", "pptx", "doc", "xls", "ppt",
        "md", "txt", "rtf", "pdf",
        "raw", "arw", "cr2", "cr3", "nef", "dng", "orf", "rw2",
        "prproj", "aep", "fcpxml", "logicx", "band", "als", "flp",
        "sqlite", "db",
    ]

    /// 어딘가에서 받아온 것들. 다시 받으면 된다.
    static let acquiredExtensions: Set<String> = [
        "dmg", "pkg", "iso", "msi", "xip", "ipsw", "deb", "rpm",
        "zip", "tar", "gz", "bz2", "xz", "7z", "rar",
        "ipa", "apk", "jar", "whl",
    ]

    /// 만들어진 것들. 다시 만들면 된다.
    static let generatedExtensions: Set<String> = [
        "o", "a", "so", "dylib", "class", "pyc", "log", "tmp", "cache",
        "dSYM", "swiftmodule", "framework",
    ]

    /// 자격 증명. 잃으면 되돌릴 방법이 없다.
    static let credentialExtensions: Set<String> = [
        "pem", "p12", "pfx", "keychain", "mobileprovision", "cer", "p8", "jks", "keystore",
    ]

    /// 경로에 이 이름이 들어 있으면 만들어진 산출물로 본다.
    static let generatedDirectoryNames: Set<String> = [
        "Caches", "Cache", "DerivedData", "node_modules", "build", ".build",
        "Pods", ".gradle", "__pycache__", ".next", "dist", "target",
        "CoreSimulator", "DeviceSupport", "_cacache", ".pub-cache",
    ]

    /// 이 안은 사용자가 직접 만든 것으로 본다.
    static let authoredDirectories = ["Documents", "Desktop", "Pictures", "Movies", "Music"]

    /// 클라우드 동기화 폴더.
    static let cloudDirectories = [
        "Library/Mobile Documents", "Library/CloudStorage",
        "Dropbox", "Google Drive", "OneDrive",
    ]

    /// 자격 증명 폴더.
    static let credentialDirectories = [
        ".ssh", ".gnupg", ".aws", ".kube", "Library/Keychains",
        "Library/MobileDevice/Provisioning Profiles",
    ]

    // MARK: -

    public func assess(_ url: URL) -> ImportanceAssessment {
        let target = url.standardizedFileURL
        let path = target.path
        let name = target.lastPathComponent
        let ext = target.pathExtension.lowercased()
        let components = target.pathComponents

        var signals: [ImportanceSignal] = []
        var level = ImportanceLevel.replaceable
        var recoverability = Recoverability.unknown

        let isDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let sizeBytes = quickSize(target, isDirectory: isDirectory)

        // ── 자격 증명이면 여기서 끝. 다른 신호를 볼 것도 없다. ──────────
        if ImportanceAssessor.credentialExtensions.contains(ext) {
            signals.append(.init(direction: .raises, title: "자격 증명 파일",
                                 detail: "확장자 .\(ext) — 인증서나 키입니다."))
            level = .critical
        }
        for directory in ImportanceAssessor.credentialDirectories
        where path.hasPrefix(paths.resolve(directory).path + "/") || path == paths.resolve(directory).path {
            signals.append(.init(direction: .raises, title: "자격 증명 폴더",
                                 detail: "~/\(directory) 안입니다."))
            level = .critical
        }

        if level != .critical {
            // ── 만들어진 산출물인가 ──────────────────────────────────
            var generatedHit: String?
            for component in components where ImportanceAssessor.generatedDirectoryNames.contains(component) {
                generatedHit = component
                break
            }
            if let hit = generatedHit {
                signals.append(.init(direction: .lowers, title: "자동 생성 폴더",
                                     detail: "경로에 '\(hit)' 가 있습니다. 도구가 만들어낸 것입니다."))
                level = .disposable
                recoverability = .regenerates
            } else if ImportanceAssessor.generatedExtensions.contains(ext) {
                signals.append(.init(direction: .lowers, title: "빌드 산출물",
                                     detail: "확장자 .\(ext) — 다시 빌드하면 만들어집니다."))
                level = .disposable
                recoverability = .regenerates
            }

            // ── 사용자가 직접 만든 것인가 ─────────────────────────────
            for directory in ImportanceAssessor.authoredDirectories
            where path.hasPrefix(paths.resolve(directory).path + "/") {
                signals.append(.init(direction: .raises, title: "사용자 폴더",
                                     detail: "~/\(directory) 안입니다. 직접 넣어둔 것으로 봅니다."))
                level = max(level, .personal)
            }
            if ImportanceAssessor.authoredExtensions.contains(ext) {
                signals.append(.init(direction: .raises, title: "작업 파일",
                                     detail: "확장자 .\(ext) — 직접 만드는 종류의 파일입니다."))
                level = max(level, .personal)
            }

            // ── 받아온 것인가 ─────────────────────────────────────────
            if ImportanceAssessor.acquiredExtensions.contains(ext) {
                signals.append(.init(direction: .lowers, title: "받아온 파일",
                                     detail: "확장자 .\(ext) — 설치 파일이나 압축 파일입니다."))
                level = min(level, .replaceable)
                if recoverability == .unknown { recoverability = .redownloadable }
            }
            if ExtendedAttributes.exists("com.apple.quarantine", at: path) {
                signals.append(.init(direction: .lowers, title: "인터넷에서 받음",
                                     detail: "다운로드 표시(quarantine)가 붙어 있습니다."))
                level = min(level, .replaceable)
                if recoverability == .unknown { recoverability = .redownloadable }
            }
        }

        // ── 되찾을 수 있는가 ──────────────────────────────────────────
        for directory in ImportanceAssessor.cloudDirectories
        where path.hasPrefix(paths.resolve(directory).path + "/") {
            signals.append(.init(direction: .context, title: "클라우드 동기화 폴더",
                                 detail: "~/\(directory) 안입니다. 여기서 지우면 클라우드에서도 지워질 수 있습니다."))
            recoverability = .syncedElsewhere
        }

        switch GitRepository.state(for: target) {
        case .withRemote(let root):
            signals.append(.init(direction: .context, title: "git 저장소 (원격 있음)",
                                 detail: "\(paths.abbreviate(root)) — 커밋·푸시된 내용은 다시 받을 수 있습니다."))
            if recoverability == .unknown { recoverability = .inVersionControl }
        case .withoutRemote(let root):
            signals.append(.init(direction: .raises, title: "git 저장소 (원격 없음)",
                                 detail: "\(paths.abbreviate(root)) — 올려둔 곳이 없어 이 맥에만 있습니다."))
            level = max(level, .personal)
            recoverability = .onlyCopy
        case .none:
            break
        }

        // ── 마지막으로 연 시각 ────────────────────────────────────────
        if let days = daysSinceLastAccess(path) {
            if days >= 365 {
                signals.append(.init(direction: .lowers, title: "오래 열지 않음",
                                     detail: "마지막으로 연 지 \(days)일 지났습니다."))
            } else if days <= 7 {
                signals.append(.init(direction: .raises, title: "최근에 사용",
                                     detail: "\(days)일 전에 열었습니다. 지금 쓰는 중일 수 있습니다."))
                level = max(level, .replaceable)
            } else {
                signals.append(.init(direction: .context, title: "마지막 사용",
                                     detail: "\(days)일 전"))
            }
        }

        return ImportanceAssessor.resolve(
            level: level,
            recoverability: recoverability,
            signals: signals,
            sizeBytes: sizeBytes
        )
    }

    // MARK: - 판정

    /// 두 축(중요도 · 복구 가능성)을 하나의 결론으로 합친다.
    ///
    /// 애매하면 언제나 **보수적인 쪽**으로 기운다. 못 지우는 실패는 되돌릴 수 있고,
    /// 잘못 지우는 실패는 되돌릴 수 없다.
    static func resolve(
        level: ImportanceLevel,
        recoverability: Recoverability,
        signals: [ImportanceSignal],
        sizeBytes: Int64
    ) -> ImportanceAssessment {

        let verdict: DeletionVerdict
        let headline: String
        let cost: String

        switch level {
        case .critical:
            verdict = .keep
            headline = "자격 증명이거나 유일본입니다. 이 앱은 이런 항목을 지우지 않습니다."
            cost = "되돌릴 방법이 없습니다."

        case .personal:
            switch recoverability {
            case .inVersionControl:
                verdict = .checkFirst
                headline = "직접 만든 것이지만 원격 저장소에 올라가 있습니다."
                cost = "다시 받으면 됩니다. 커밋하지 않은 변경은 사라집니다."
            case .syncedElsewhere:
                verdict = .checkFirst
                headline = "직접 만든 것이고, 클라우드 동기화 폴더 안입니다."
                cost = "여기서 지우면 다른 기기와 클라우드에서도 사라집니다."
            default:
                verdict = .keep
                headline = "직접 만든 것으로 보이고, 다른 사본을 찾지 못했습니다."
                cost = "지우면 같은 걸 다시 만들 수 없습니다."
            }

        case .replaceable:
            verdict = .checkFirst
            switch recoverability {
            case .redownloadable:
                headline = "다시 받을 수 있는 파일입니다."
                cost = sizeBytes > 0
                    ? "\(ByteFormat.string(sizeBytes)) 를 다시 내려받아야 합니다."
                    : "다시 내려받아야 합니다."
            case .inVersionControl:
                headline = "원격 저장소에 있는 내용입니다."
                cost = "다시 받으면 됩니다."
            case .syncedElsewhere:
                headline = "클라우드 동기화 폴더 안입니다."
                cost = "여기서 지우면 다른 기기에서도 사라집니다."
            case .onlyCopy:
                return ImportanceAssessment(
                    verdict: .keep,
                    headline: "사본이나 원격을 찾지 못했습니다.",
                    cost: "지우면 되돌릴 방법이 없을 수 있습니다.",
                    level: level, recoverability: recoverability, signals: signals
                )
            default:
                headline = "다시 만들거나 다시 받을 수 있어 보이지만, 확실하지는 않습니다."
                cost = "다시 구하는 데 시간이 걸립니다."
            }

        case .disposable:
            verdict = .safe
            headline = "도구가 만들어낸 것입니다. 필요하면 다시 만들어집니다."
            cost = sizeBytes > 0
                ? "없음. 다음에 쓸 때 한 번 느려질 수 있습니다."
                : "없음."
        }

        return ImportanceAssessment(
            verdict: verdict,
            headline: headline,
            cost: cost,
            level: level,
            recoverability: recoverability,
            signals: signals
        )
    }

    // MARK: - 값싼 조회들

    /// 폴더는 안을 훑지 않는다. 이 판단은 목록을 펼칠 때마다 불리므로 빨라야 한다.
    private func quickSize(_ url: URL, isDirectory: Bool) -> Int64 {
        guard !isDirectory else { return 0 }
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        if let allocated = values?.totalFileAllocatedSize { return Int64(allocated) }
        if let logical = values?.fileSize { return Int64(logical) }
        return 0
    }

    /// 마지막으로 연 시각.
    ///
    /// Spotlight 의 `kMDItemLastUsedDate` 가 더 정확하지만 색인이 없으면 답을 못 준다.
    /// `atime` 은 근사치일 뿐이라 **약한 신호로만** 쓴다 — 이것만으로 판정이 뒤집히지 않는다.
    private func daysSinceLastAccess(_ path: String) -> Int? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        let accessed = Date(timeIntervalSince1970: TimeInterval(st.st_atimespec.tv_sec))
        let days = Int(Date().timeIntervalSince(accessed) / 86_400)
        return days >= 0 ? days : nil
    }
}

/// 확장 속성 조회.
enum ExtendedAttributes {
    /// 이 속성이 붙어 있는가. 값은 읽지 않는다 — 존재 여부만 알면 되는 용도다.
    static func exists(_ name: String, at path: String) -> Bool {
        getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }
}

/// git 저장소 판별.
///
/// 명령을 실행하지 않고 `.git/config` 를 읽는다. `git` 이 없어도 되고, 훨씬 빠르다.
enum GitRepository {
    enum State {
        case none
        case withRemote(root: URL)
        case withoutRemote(root: URL)
    }

    /// 위로 최대 12단계까지 `.git` 을 찾는다.
    static func state(for url: URL, maximumDepth: Int = 12) -> State {
        var current = url.standardizedFileURL
        var depth = 0

        while depth < maximumDepth, current.path != "/" {
            let dotGit = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: dotGit.path) {
                let config = dotGit.appendingPathComponent("config")
                if let text = try? String(contentsOf: config, encoding: .utf8), text.contains("[remote ") {
                    return .withRemote(root: current)
                }
                // `.git` 이 파일이면 worktree 나 submodule 이다. 원격 여부를 여기서는 알 수 없으므로
                // 없다고 가정한다 — 보수적인 쪽이다.
                return .withoutRemote(root: current)
            }
            current = current.deletingLastPathComponent()
            depth += 1
        }
        return .none
    }
}
