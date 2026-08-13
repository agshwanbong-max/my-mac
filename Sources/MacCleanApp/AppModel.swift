#if os(macOS)
import AppKit
import Combine
import Foundation
import MacCleanCore
import SwiftUI

/// UI 상태 전부. 코어는 이 타입을 모른다 (한 방향 의존).
@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case executing(current: Int, total: Int)
        case finished
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var report: ScanReport?
    @Published private(set) var outcomes: [CleanupOutcome] = []
    @Published private(set) var hasFullDiskAccess = true
    /// 지금 무엇을 검사하고 있는지. 진행 표시에 쓴다.
    @Published private(set) var statusText = ""

    /// 사이드바 선택. nil 이면 전체 보기.
    @Published var selectedCategory: FindingCategory?
    /// 사용자가 체크한 항목의 id.
    @Published var selection: Set<String> = []
    /// 홈 전체를 훑어 대용량 파일까지 찾을지. 가장 무거운 검사라 기본은 꺼둔다.
    @Published var includeLargeFiles = false

    @Published var isConfirming = false
    @Published var isShowingResults = false

    private let paths = UserPaths.current()
    private var scanTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

    // MARK: - 파생 상태

    /// 현재 화면에 보여줄 항목.
    var visibleFindings: [Finding] {
        guard let report else { return [] }
        guard let category = selectedCategory else { return report.findings }
        return report.findings(in: category)
    }

    var selectedFindings: [Finding] {
        guard let report else { return [] }
        return report.findings.filter { selection.contains($0.id) && $0.isSelectable }
    }

    var selectedBytes: Int64 {
        selectedFindings.reduce(0) { $0 + $1.reclaimableBytes }
    }

    var selectionIncludesIrreversible: Bool {
        selectedFindings.contains { !$0.removal.isReversible }
    }

    var isBusy: Bool {
        switch phase {
        case .scanning, .executing: return true
        default: return false
        }
    }

    var canClean: Bool {
        !selectedFindings.isEmpty && !isBusy
    }

    // MARK: - 검사

    func startScan() {
        scanTask?.cancel()

        phase = .scanning
        statusText = "검사를 시작합니다…"
        outcomes = []
        selection = []

        let paths = self.paths
        let includeLargeFiles = self.includeLargeFiles
        let runningIdentifiers = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })

        scanTask = Task { [weak self] in
            let fullDiskAccess = FullDiskAccessProbe.hasAccess(paths: paths)
            let context = ScanContext(
                paths: paths,
                runningBundleIdentifiers: runningIdentifiers,
                hasFullDiskAccess: fullDiskAccess
            )
            let coordinator = ScanCoordinator.standard(paths: paths, includeLargeFiles: includeLargeFiles)

            let result = await coordinator.run(
                context: context,
                progress: { identifier in
                    Task { @MainActor [weak self] in
                        self?.statusText = ScannerLabel.text(for: identifier)
                    }
                },
                isCancelled: { Task.isCancelled }
            )

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.hasFullDiskAccess = fullDiskAccess
                self.report = result
                self.statusText = ""
                // 보수적 정책: 안전 등급이면서 되돌릴 수 있는 항목만 기본 체크.
                // 그마저도 확인 창을 한 번 더 통과해야 실행된다.
                self.selection = Set(
                    result.findings
                        .filter { $0.isSelectable && $0.risk.defaultsToSelected && $0.removal.isReversible }
                        .map { $0.id }
                )
                self.phase = .ready
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        statusText = ""
        phase = report == nil ? .idle : .ready
    }

    // MARK: - 실행

    func requestCleanup() {
        guard canClean else { return }
        isConfirming = true
    }

    func performCleanup(dryRun: Bool) {
        isConfirming = false
        guard !isBusy else { return }

        let targets = selectedFindings
        guard !targets.isEmpty else { return }

        phase = .executing(current: 0, total: targets.count)

        let paths = self.paths
        cleanupTask = Task { [weak self] in
            let executor = CleanupExecutor(paths: paths, dryRun: dryRun)
            let results = executor.execute(
                targets,
                progress: { current, total in
                    Task { @MainActor [weak self] in
                        self?.phase = .executing(current: current, total: total)
                    }
                },
                isCancelled: { Task.isCancelled }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.outcomes = results
                self.phase = .finished
                self.isShowingResults = true
            }
        }
    }

    // MARK: - 선택

    func toggle(_ finding: Finding) {
        guard finding.isSelectable else { return }
        if selection.contains(finding.id) {
            selection.remove(finding.id)
        } else {
            selection.insert(finding.id)
        }
    }

    func isSelected(_ finding: Finding) -> Bool {
        selection.contains(finding.id)
    }

    /// 지금 보이는 항목 전체를 켜거나 끈다.
    func setSelectionForVisible(_ selected: Bool) {
        for finding in visibleFindings where finding.isSelectable {
            if selected {
                selection.insert(finding.id)
            } else {
                selection.remove(finding.id)
            }
        }
    }

    var visibleSelectableCount: Int {
        visibleFindings.filter { $0.isSelectable }.count
    }

    var allVisibleSelected: Bool {
        let selectable = visibleFindings.filter { $0.isSelectable }
        return !selectable.isEmpty && selectable.allSatisfy { selection.contains($0.id) }
    }

    // MARK: - 시스템 연동

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ finding: Finding) {
        guard let path = finding.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
#endif
