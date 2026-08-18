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
        let ext = target.pathExtension.lowercased()
        let components = target.pathComponents

        var signals: [ImportanceSignal] = []
        var level = ImportanceLevel.replaceable
        var recoverability = Recoverability.unknown

        let isDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let sizeBytes = quickSize(target, isDirectory: isDirectory)

        // ── 자격 증명이면 여기서 끝. 다른 신호를 볼 것도 없다. ──────────
        if ImportanceAssessor.credentialExtensions.contains(ext) {
            signals.append(.init(direction: .raises, title: L("signal.credentialFile"),
                                 detail: L("signal.credentialFile.detail", ext)))
            level = .critical
        }
        for directory in ImportanceAssessor.credentialDirectories
        where path.hasPrefix(paths.resolve(directory).path + "/") || path == paths.resolve(directory).path {
            signals.append(.init(direction: .raises, title: L("signal.credentialFolder"),
                                 detail: L("signal.credentialFolder.detail", directory)))
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
                signals.append(.init(direction: .lowers, title: L("signal.generatedFolder"),
                                     detail: L("signal.generatedFolder.detail", hit)))
                level = .disposable
                recoverability = .regenerates
            } else if ImportanceAssessor.generatedExtensions.contains(ext) {
                signals.append(.init(direction: .lowers, title: L("signal.buildArtifact"),
                                     detail: L("signal.buildArtifact.detail", ext)))
                level = .disposable
                recoverability = .regenerates
            }

            // ── 사용자가 직접 만든 것인가 ─────────────────────────────
            for directory in ImportanceAssessor.authoredDirectories
            where path.hasPrefix(paths.resolve(directory).path + "/") {
                signals.append(.init(direction: .raises, title: L("signal.userFolder"),
                                     detail: L("signal.userFolder.detail", directory)))
                level = max(level, .personal)
            }
            if ImportanceAssessor.authoredExtensions.contains(ext) {
                signals.append(.init(direction: .raises, title: L("signal.workFile"),
                                     detail: L("signal.workFile.detail", ext)))
                level = max(level, .personal)
            }

            // ── 받아온 것인가 ─────────────────────────────────────────
            if ImportanceAssessor.acquiredExtensions.contains(ext) {
                signals.append(.init(direction: .lowers, title: L("signal.fetchedFile"),
                                     detail: L("signal.fetchedFile.detail", ext)))
                level = min(level, .replaceable)
                if recoverability == .unknown { recoverability = .redownloadable }
            }
            if ExtendedAttributes.exists("com.apple.quarantine", at: path) {
                signals.append(.init(direction: .lowers, title: L("signal.fromInternet"),
                                     detail: L("signal.fromInternet.detail")))
                level = min(level, .replaceable)
                if recoverability == .unknown { recoverability = .redownloadable }
            }
        }

        // ── 되찾을 수 있는가 ──────────────────────────────────────────
        for directory in ImportanceAssessor.cloudDirectories
        where path.hasPrefix(paths.resolve(directory).path + "/") {
            signals.append(.init(direction: .context, title: L("signal.cloudFolder"),
                                 detail: L("signal.cloudFolder.detail", directory)))
            recoverability = .syncedElsewhere
        }

        switch GitRepository.state(for: target) {
        case .withRemote(let root):
            signals.append(.init(direction: .context, title: L("signal.gitWithRemote"),
                                 detail: L("signal.gitWithRemote.detail", paths.abbreviate(root))))
            if recoverability == .unknown { recoverability = .inVersionControl }
        case .withoutRemote(let root):
            signals.append(.init(direction: .raises, title: L("signal.gitNoRemote"),
                                 detail: L("signal.gitNoRemote.detail", paths.abbreviate(root))))
            level = max(level, .personal)
            recoverability = .onlyCopy
        case .none:
            break
        }

        // ── 마지막으로 연 시각 ────────────────────────────────────────
        if let days = daysSinceLastAccess(path) {
            if days >= 365 {
                signals.append(.init(direction: .lowers, title: L("signal.notOpenedLong"),
                                     detail: L("signal.notOpenedLong.detail", days)))
            } else if days <= 7 {
                signals.append(.init(direction: .raises, title: L("signal.recentlyUsed"),
                                     detail: L("signal.recentlyUsed.detail", days)))
                // 최근에 썼다는 사실이 **다시 만들어지는 것**을 소중하게 만들지는 않는다.
                // DerivedData 는 오늘 빌드했든 한 달 전에 빌드했든 다음 빌드에 다시 생긴다.
                // 이걸 안 걸러내면 한창 개발 중인 프로젝트의 빌드 산출물이 전부
                // '확인 후' 로 내려앉는다 — 정작 가장 확실하게 지워도 되는 것들인데.
                //
                // 최근 사용 여부는 **정체를 모르는 파일**을 판단할 때만 의미가 있다.
                if recoverability != .regenerates {
                    level = max(level, .replaceable)
                }
            } else {
                signals.append(.init(direction: .context, title: L("signal.lastUsed"),
                                     detail: L("signal.lastUsed.detail", days)))
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
            headline = L("assess.critical.headline")
            cost = L("assess.critical.cost")

        case .personal:
            switch recoverability {
            case .inVersionControl:
                verdict = .checkFirst
                headline = L("assess.personalInVCS.headline")
                cost = L("assess.personalInVCS.cost")
            case .syncedElsewhere:
                verdict = .checkFirst
                headline = L("assess.personalInCloud.headline")
                cost = L("assess.personalInCloud.cost")
            default:
                verdict = .keep
                headline = L("assess.personalOnly.headline")
                cost = L("assess.personalOnly.cost")
            }

        case .replaceable:
            verdict = .checkFirst
            switch recoverability {
            case .redownloadable:
                headline = L("assess.redownloadable.headline")
                cost = sizeBytes > 0
                    ? L("assess.redownloadable.cost.sized", ByteFormat.string(sizeBytes))
                    : L("assess.redownloadable.cost")
            case .inVersionControl:
                headline = L("assess.inVCS.headline")
                cost = L("assess.inVCS.cost")
            case .syncedElsewhere:
                headline = L("assess.inCloud.headline")
                cost = L("assess.inCloud.cost")
            case .onlyCopy:
                return ImportanceAssessment(
                    verdict: .keep,
                    headline: L("assess.noCopy.headline"),
                    cost: L("assess.noCopy.cost"),
                    level: level, recoverability: recoverability, signals: signals
                )
            default:
                headline = L("assess.probablyReplaceable.headline")
                cost = L("assess.probablyReplaceable.cost")
            }

        case .disposable:
            verdict = .safe
            headline = L("assess.disposable.headline")
            cost = sizeBytes > 0
                ? L("assess.disposable.cost.slow")
                : L("assess.disposable.cost")
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
