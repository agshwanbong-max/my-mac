import Foundation

/// 실행 결과 한 건.
public struct CleanupOutcome: Sendable, Identifiable {
    public enum Status: String, Sendable {
        case removed          // 휴지통으로 이동 완료
        case deleted          // 완전 삭제 완료
        case simulated        // 미리보기(dry run) — 아무것도 하지 않음
        case skipped          // 안전 검사에서 걸러짐
        case failed           // 시도했으나 실패

        public var localizedTitle: String {
            switch self {
            case .removed: return "휴지통으로 이동"
            case .deleted: return "삭제 완료"
            case .simulated: return "미리보기"
            case .skipped: return "건너뜀"
            case .failed: return "실패"
            }
        }
    }

    public var id: String { finding.id }
    public let finding: Finding
    public let status: Status
    public let bytes: Int64
    public let message: String
    public let trashedTo: URL?
}

/// 사용자가 승인한 항목을 실제로 처리한다.
///
/// 이 타입의 존재 이유는 하나다: **스캔 결과를 믿지 않는 것.**
/// 스캔과 실행 사이에는 시간이 흐른다. 그 사이에 파일이 커졌을 수도, 사용자가 다시 쓰기 시작했을 수도,
/// 경로가 심볼릭 링크로 바뀌었을 수도 있다. 그래서 항목마다 처음부터 다시 검사한다.
public struct CleanupExecutor: @unchecked Sendable {   // FileManager 보관 — PathGuard 의 설명 참고

    /// 미리보기 모드. `true` 면 아무것도 건드리지 않고 무슨 일이 일어날지만 계산한다.
    public let dryRun: Bool

    private let paths: UserPaths
    private let guardian: PathGuard
    private let audit: AuditLog
    private let runner: ShellRunner
    private let fileManager: FileManager
    private let usage = DiskUsage()

    public init(
        paths: UserPaths,
        dryRun: Bool,
        audit: AuditLog? = nil,
        runner: ShellRunner = ShellRunner(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.dryRun = dryRun
        self.guardian = PathGuard(paths: paths, fileManager: fileManager)
        self.audit = audit ?? AuditLog(paths: paths)
        self.runner = runner
        self.fileManager = fileManager
    }

    public func execute(
        _ findings: [Finding],
        progress: (Int, Int) -> Void = { _, _ in },
        isCancelled: () -> Bool = { false }
    ) -> [CleanupOutcome] {
        var outcomes: [CleanupOutcome] = []
        let total = findings.count

        for (index, finding) in findings.enumerated() {
            if isCancelled() {
                outcomes.append(skip(finding, "사용자가 중단했습니다."))
                continue
            }
            progress(index + 1, total)
            outcomes.append(process(finding))
        }

        return outcomes
    }

    // MARK: -

    private func process(_ finding: Finding) -> CleanupOutcome {
        // ── 1. 애초에 손대면 안 되는 항목인가 ─────────────────────────
        guard finding.isSelectable else {
            return skip(finding, "안내 전용 항목입니다. 이 앱은 이 항목을 건드리지 않습니다.")
        }

        // ── 2. 도구 명령으로 처리하는 항목 ───────────────────────────
        if finding.removal == .toolCommand {
            return processToolCommand(finding)
        }

        // ── 3. 경로와 제약이 둘 다 있어야 한다 ───────────────────────
        guard let path = finding.path else {
            return skip(finding, "경로가 없습니다.")
        }
        guard let constraints = finding.constraints else {
            // 제약 없이 만들어진 후보는 검증할 방법이 없다. 지우지 않는다.
            return skip(finding, "안전 제약 정보가 없어 검증할 수 없습니다.")
        }

        // ── 4. 관문 재통과 (스캔 때와 똑같은 제약으로) ───────────────
        let decision = guardian.evaluate(path, constraints: constraints)
        guard decision.allowed else {
            return skip(finding, "안전 검사에서 걸렀습니다 [\(decision.gate)] \(decision.reason)")
        }

        // ── 5. 자격 증명·유일본이 아닌가 (마지막 그물) ────────────────
        // 규칙과 관문을 다 통과했어도, 경로 자체를 다시 들여다본다.
        // 규칙을 새로 추가하다 실수해서 자격 증명이 후보로 올라오는 경우를 막는 그물이다.
        // `.critical` 만 막는다 — 그 아래는 사용자가 판단할 몫이라 여기서 가로채지 않는다.
        let assessment = ImportanceAssessor(paths: paths).assess(path)
        if assessment.level == .critical {
            return skip(finding, "자격 증명이나 유일본으로 보여 삭제하지 않았습니다: \(assessment.headline)")
        }

        // ── 6. 스캔 이후 변경되지 않았는가 ───────────────────────────
        let measurement = usage.measure(path)
        if let scanned = finding.lastModified, let current = measurement.newestModification {
            // 1초 오차는 파일시스템 타임스탬프 정밀도 문제로 흔하다.
            if current.timeIntervalSince(scanned) > 1 {
                return skip(finding, "검사한 뒤에 내용이 바뀌었습니다. 지금 사용 중일 수 있어 건너뜁니다. 다시 검사해 주세요.")
            }
        }

        // 실제 회수량은 지금 다시 잰 값을 쓴다.
        let bytes = measurement.allocatedBytes

        // ── 7. 미리보기 ──────────────────────────────────────────────
        if dryRun {
            return CleanupOutcome(
                finding: finding,
                status: .simulated,
                bytes: bytes,
                message: "\(finding.removal.localizedTitle) 예정 · \(ByteFormat.string(bytes))",
                trashedTo: nil
            )
        }

        // ── 8. 실행 ──────────────────────────────────────────────────
        switch finding.removal {
        case .trashItem:
            return moveToTrash(finding, path: path, bytes: bytes)
        case .permanentDelete:
            return permanentlyDelete(finding, path: path, bytes: bytes)
        case .adviseOnly, .toolCommand:
            return skip(finding, "여기까지 올 수 없는 경로입니다.")
        }
    }

    private func moveToTrash(_ finding: Finding, path: URL, bytes: Int64) -> CleanupOutcome {
        do {
            var resulting: NSURL?
            try fileManager.trashItem(at: path, resultingItemURL: &resulting)
            let destination = resulting as URL?

            record(finding, action: "trash", bytes: bytes, succeeded: true, trashedTo: destination?.path, message: nil)
            return CleanupOutcome(
                finding: finding,
                status: .removed,
                bytes: bytes,
                message: "휴지통으로 옮겼습니다 · \(ByteFormat.string(bytes))",
                trashedTo: destination
            )
        } catch {
            // 휴지통 이동이 실패해도 **완전 삭제로 대체하지 않는다.** 그냥 포기한다.
            // 되돌릴 수 없는 방식으로 조용히 바뀌는 것보다 안 지우는 게 낫다.
            record(finding, action: "trash", bytes: bytes, succeeded: false, trashedTo: nil, message: error.localizedDescription)
            return CleanupOutcome(
                finding: finding,
                status: .failed,
                bytes: 0,
                message: "휴지통으로 옮기지 못했습니다: \(error.localizedDescription)",
                trashedTo: nil
            )
        }
    }

    private func permanentlyDelete(_ finding: Finding, path: URL, bytes: Int64) -> CleanupOutcome {
        do {
            try fileManager.removeItem(at: path)
            record(finding, action: "delete", bytes: bytes, succeeded: true, trashedTo: nil, message: nil)
            return CleanupOutcome(
                finding: finding,
                status: .deleted,
                bytes: bytes,
                message: "삭제했습니다 · \(ByteFormat.string(bytes))",
                trashedTo: nil
            )
        } catch {
            record(finding, action: "delete", bytes: bytes, succeeded: false, trashedTo: nil, message: error.localizedDescription)
            return CleanupOutcome(
                finding: finding,
                status: .failed,
                bytes: 0,
                message: "삭제하지 못했습니다: \(error.localizedDescription)",
                trashedTo: nil
            )
        }
    }

    private func processToolCommand(_ finding: Finding) -> CleanupOutcome {
        guard let command = finding.toolCommand else {
            return skip(finding, "실행할 명령이 없습니다.")
        }
        guard command.isAllowed else {
            return skip(finding, "허용되지 않은 명령입니다: \(command.displayString)")
        }

        if dryRun {
            return CleanupOutcome(
                finding: finding,
                status: .simulated,
                bytes: finding.reclaimableBytes,
                message: "실행 예정: \(command.displayString)",
                trashedTo: nil
            )
        }

        do {
            let result = try runner.run(executable: command.executable, arguments: command.arguments, timeout: 120)
            let succeeded = result.succeeded
            record(finding, action: "tool", bytes: finding.reclaimableBytes, succeeded: succeeded, trashedTo: nil,
                   message: succeeded ? command.displayString : result.standardError)
            return CleanupOutcome(
                finding: finding,
                status: succeeded ? .deleted : .failed,
                bytes: succeeded ? finding.reclaimableBytes : 0,
                message: succeeded
                    ? "\(command.displayString) 실행 완료 · \(ByteFormat.string(finding.reclaimableBytes))"
                    : "명령 실패: \(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))",
                trashedTo: nil
            )
        } catch {
            record(finding, action: "tool", bytes: 0, succeeded: false, trashedTo: nil, message: error.localizedDescription)
            return CleanupOutcome(
                finding: finding,
                status: .failed,
                bytes: 0,
                message: "명령을 실행하지 못했습니다: \(error.localizedDescription)",
                trashedTo: nil
            )
        }
    }

    private func skip(_ finding: Finding, _ message: String) -> CleanupOutcome {
        record(finding, action: "skip", bytes: 0, succeeded: false, trashedTo: nil, message: message)
        return CleanupOutcome(finding: finding, status: .skipped, bytes: 0, message: message, trashedTo: nil)
    }

    private func record(
        _ finding: Finding,
        action: String,
        bytes: Int64,
        succeeded: Bool,
        trashedTo: String?,
        message: String?
    ) {
        guard !dryRun else { return }
        audit.append(AuditLog.Entry(
            timestamp: Date(),
            action: action,
            ruleID: finding.ruleID,
            path: finding.path?.path,
            bytes: bytes,
            removal: finding.removal.rawValue,
            trashedTo: trashedTo,
            succeeded: succeeded,
            message: message
        ))
    }
}
