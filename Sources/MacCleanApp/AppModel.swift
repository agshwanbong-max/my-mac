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

    /// 사용자가 체크한 항목의 id.
    @Published var selection: Set<String> = []
    /// 확인 시트 표시 여부.
    @Published var isConfirming = false
    /// 결과 시트 표시 여부.
    @Published var isShowingResults = false
    /// 접힌 카테고리.
    @Published var collapsedCategories: Set<FindingCategory> = []

    private let paths = UserPaths.current()
    private var cancelRequested = false

    // MARK: - 파생 상태

    var selectedFindings: [Finding] {
        guard let report else { return [] }
        return report.findings.filter { selection.contains($0.id) && $0.isSelectable }
    }

    var selectedBytes: Int64 {
        selectedFindings.reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// 되돌릴 수 없는 항목이 선택에 포함돼 있는가. 확인 창에서 크게 경고한다.
    var selectionIncludesIrreversible: Bool {
        selectedFindings.contains { !$0.removal.isReversible }
    }

    var isBusy: Bool {
        switch phase {
        case .scanning, .executing: return true
        default: return false
        }
    }

    // MARK: - 검사

    func startScan() {
        guard !isBusy else { return }
        cancelRequested = false
        phase = .scanning
        outcomes = []
        selection = []

        let paths = self.paths
        let runningIdentifiers = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })

        Task.detached(priority: .userInitiated) {
            let fullDiskAccess = FullDiskAccessProbe.hasAccess(paths: paths)
            let context = ScanContext(
                paths: paths,
                runningBundleIdentifiers: runningIdentifiers,
                hasFullDiskAccess: fullDiskAccess
            )
            let coordinator = ScanCoordinator.standard(paths: paths)
            let result = coordinator.run(context: context)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.hasFullDiskAccess = fullDiskAccess
                self.report = result
                // 보수적 정책: 안전 등급만 기본으로 체크한다.
                // 그마저도 '정리 실행' 을 누르고 확인 창을 한 번 더 통과해야 한다.
                self.selection = Set(
                    result.findings
                        .filter { $0.isSelectable && $0.risk.defaultsToSelected && $0.removal.isReversible }
                        .map { $0.id }
                )
                self.phase = .ready
            }
        }
    }

    // MARK: - 실행

    func requestCleanup() {
        guard !selectedFindings.isEmpty else { return }
        isConfirming = true
    }

    /// 실제 실행. 확인 창에서만 호출된다.
    func performCleanup(dryRun: Bool) {
        isConfirming = false
        guard !isBusy else { return }

        let targets = selectedFindings
        guard !targets.isEmpty else { return }

        cancelRequested = false
        phase = .executing(current: 0, total: targets.count)

        let paths = self.paths
        Task.detached(priority: .userInitiated) { [weak self] in
            let executor = CleanupExecutor(paths: paths, dryRun: dryRun)
            let results = executor.execute(
                targets,
                progress: { current, total in
                    Task { @MainActor in
                        self?.phase = .executing(current: current, total: total)
                    }
                },
                isCancelled: { false }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.outcomes = results
                self.phase = .finished
                self.isShowingResults = true
            }
        }
    }

    func toggle(_ finding: Finding) {
        guard finding.isSelectable else { return }
        if selection.contains(finding.id) {
            selection.remove(finding.id)
        } else {
            selection.insert(finding.id)
        }
    }

    func setSelection(for category: FindingCategory, selected: Bool) {
        guard let report else { return }
        for finding in report.findings(in: category) where finding.isSelectable {
            if selected {
                selection.insert(finding.id)
            } else {
                selection.remove(finding.id)
            }
        }
    }

    func toggleCollapse(_ category: FindingCategory) {
        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
        } else {
            collapsedCategories.insert(category)
        }
    }

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
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
