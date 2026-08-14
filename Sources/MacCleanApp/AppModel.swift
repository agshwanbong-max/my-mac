#if os(macOS)
import AppKit
import Combine
import Foundation
import MacCleanCore
import SwiftUI

/// `sheet(item:)` 에 넘기려고 URL 을 감싼 것.
struct BrowsableDirectory: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
}

/// UI 상태 전부. 코어는 이 타입을 모른다 (한 방향 의존).
@MainActor
final class AppModel: ObservableObject {

    /// 사이드바 항목.
    ///
    /// 예전에는 선택 타입이 `FindingCategory?` 였고 "전체" 행의 태그가 `nil` 이었다.
    /// SwiftUI 는 `nil` 선택을 "아무것도 선택 안 됨" 과 구분하지 못해서,
    /// **"전체" 를 눌러도 선택 표시가 안 되고 되돌아가지도 않았다.**
    /// 전용 타입을 쓰면 "전체" 도 어엿한 값이 된다.
    enum SidebarItem: Hashable {
        case all
        case category(FindingCategory)
    }

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
    /// 지금 무엇을 검사하고 있는지. 진행 표시 아래 줄에 쓴다.
    @Published private(set) var statusText = ""
    /// 진행 막대에 쓰는 값. 끝난 스캐너 수 / 전체 스캐너 수.
    @Published private(set) var scanProgress = ScanProgress(completed: 0, total: 1, detail: "")

    /// 사이드바 선택.
    @Published var sidebarSelection: SidebarItem = .all

    /// 탐색기로 열어둔 폴더. nil 이면 안 열려 있다.
    /// `sheet(item:)` 이 Identifiable 을 요구하는데 URL 은 그걸 갖고 있지 않아 감싼다.
    @Published var browsingDirectory: BrowsableDirectory?

    var selectedCategory: FindingCategory? {
        if case .category(let category) = sidebarSelection { return category }
        return nil
    }
    /// 사용자가 체크한 항목의 id.
    @Published var selection: Set<String> = []
    /// 홈 전체를 훑어 용량 분포와 대용량 파일까지 찾을지. 가장 무거운 검사라 기본은 꺼둔다.
    @Published var includeDeepScan = false
    /// 내용이 같은 파일을 찾을지. 파일을 전부 해시해야 해서 제일 느리다.
    @Published var includeDuplicates = false

    /// 되돌리기 창을 띄울지.
    @Published var isShowingRestore = false

    /// 첫 실행 안내를 띄울지.
    @Published var isShowingOnboarding = false
    /// 새 버전이 나왔으면 여기 담긴다.
    @Published private(set) var availableUpdate: UpdateChecker.Manifest?

    @Published var isConfirming = false
    @Published var isShowingResults = false

    private let paths = UserPaths.current()
    private var scanTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

    private static let onboardingKey = "MacClean.hasCompletedOnboarding"
    private static let lastUpdateCheckKey = "MacClean.lastUpdateCheck"

    /// 배포 서버에 올려두는 최신 버전 안내문.
    /// GitHub Releases 는 `latest/download/<파일명>` 을 항상 최신 릴리스로 넘겨준다.
    private static let manifestURL = URL(
        string: "https://github.com/agshwanbong-max/my-mac/releases/latest/download/appcast.json"
    )!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init() {
        // 첫 실행이면 검사보다 안내가 먼저다.
        // 권한 없이 검사부터 돌리면 절반만 찾아놓고 "이게 다인가" 하게 만든다.
        isShowingOnboarding = !UserDefaults.standard.bool(forKey: AppModel.onboardingKey)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: AppModel.onboardingKey)
        isShowingOnboarding = false
        if report == nil { startScan() }
    }

    // MARK: - 업데이트

    /// 하루에 한 번만 확인한다. 실패는 조용히 넘어간다 —
    /// 업데이트 확인이 안 됐다고 사용자를 귀찮게 할 이유가 없다.
    func checkForUpdatesIfDue() {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: AppModel.lastUpdateCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < 86_400 { return }
        defaults.set(Date(), forKey: AppModel.lastUpdateCheckKey)
        checkForUpdates(announceNoUpdate: false)
    }

    func checkForUpdates(announceNoUpdate: Bool) {
        let checker = UpdateChecker(manifestURL: AppModel.manifestURL, currentVersion: currentVersion)

        Task { [weak self] in
            let result = await checker.check()
            guard let self else { return }

            switch result {
            case .available(let manifest):
                self.availableUpdate = manifest
            case .upToDate:
                self.availableUpdate = nil
                if announceNoUpdate { self.updateMessage = "최신 버전을 쓰고 계십니다." }
            case .unavailable(let reason):
                if announceNoUpdate { self.updateMessage = "업데이트를 확인하지 못했습니다: \(reason)" }
            }
        }
    }

    /// 사용자가 직접 확인했을 때만 보여줄 메시지. 자동 확인에서는 쓰지 않는다.
    @Published var updateMessage: String?

    func openDownloadPage() {
        guard let manifest = availableUpdate else { return }
        NSWorkspace.shared.open(manifest.releaseNotesURL ?? manifest.downloadURL)
    }

    func dismissUpdate() {
        availableUpdate = nil
    }

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
        scanProgress = ScanProgress(completed: 0, total: 1, detail: "")
        outcomes = []
        selection = []

        let paths = self.paths
        let deepScan = self.includeDeepScan
        let findDuplicates = self.includeDuplicates
        let runningIdentifiers = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })

        // `Task {}` 는 이 클래스의 @MainActor 를 물려받는다.
        // 그러면 아래 동기 호출들이 메인 스레드에서 돌아 UI 가 멈춘다.
        // `Task.detached` 로 액터 밖에서 실행한다.
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            // 캡처한 `self` 를 안쪽 클로저에서 다시 캡처하면 Swift 6 에서 오류다.
            // 여기서 한 번만 풀어 지역 상수로 넘긴다.
            guard let model = self else { return }

            let fullDiskAccess = FullDiskAccessProbe.hasAccess(paths: paths)

            // 오래 걸리는 스캐너가 흘려보내는 상세 진행. 막대만으로는 멈춘 것처럼 보인다.
            let reporter = ScanProgressReporter { message in
                Task { @MainActor in model.statusText = message }
            }
            let context = ScanContext(
                paths: paths,
                runningBundleIdentifiers: runningIdentifiers,
                hasFullDiskAccess: fullDiskAccess,
                progress: reporter
            )
            let coordinator = ScanCoordinator.standard(paths: paths, deepScan: deepScan, findDuplicates: findDuplicates)

            let result = await coordinator.run(
                context: context,
                progress: { progress in
                    Task { @MainActor in model.scanProgress = progress }
                },
                isCancelled: { Task.isCancelled }
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                model.hasFullDiskAccess = fullDiskAccess
                model.report = result
                model.statusText = ""
                // 보수적 정책: 안전 등급이면서 되돌릴 수 있는 항목만 기본 체크.
                // 그마저도 확인 창을 한 번 더 통과해야 실행된다.
                model.selection = Set(
                    result.findings
                        .filter { $0.isSelectable && $0.risk.defaultsToSelected && $0.removal.isReversible }
                        .map { $0.id }
                )
                model.phase = .ready
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        statusText = ""
        phase = report == nil ? .idle : .ready
    }

    // MARK: - 탐색기

    /// 규칙이 없는 폴더를 직접 열어본다.
    func browse(_ url: URL) {
        browsingDirectory = BrowsableDirectory(url: url)
    }

    /// 탐색기에서 고른 항목들을 정리 대상에 얹는다.
    ///
    /// 검사 결과를 다시 만들지 않고 목록 뒤에 덧붙인다.
    /// 사용자가 직접 고른 것이므로 검사가 찾아낸 것과 섞이지 않게 별도 분류로 들어간다.
    func addManualSelections(_ findings: [Finding]) {
        guard let existing = report, !findings.isEmpty else { return }

        // 같은 경로를 두 번 담지 않는다.
        let existingPaths = Set(existing.findings.compactMap { $0.path?.path })
        let fresh = findings.filter { finding in
            guard let path = finding.path?.path else { return false }
            return !existingPaths.contains(path)
        }
        guard !fresh.isEmpty else { return }

        report = ScanReport(
            startedAt: existing.startedAt,
            finishedAt: existing.finishedAt,
            volume: existing.volume,
            findings: existing.findings + fresh,
            warnings: existing.warnings
        )
        // 직접 고른 항목은 자동으로 체크한다 — 이미 고르는 행위를 한 번 했기 때문이다.
        // 그래도 실행하려면 확인 창을 한 번 더 통과해야 한다.
        for finding in fresh { selection.insert(finding.id) }
        sidebarSelection = .category(.manualSelection)
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
        // 삭제는 동기 작업이다. 메인 액터에서 돌리면 진행률 표시가 멈춘다.
        cleanupTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let model = self else { return }

            let executor = CleanupExecutor(paths: paths, dryRun: dryRun)
            let results = executor.execute(
                targets,
                progress: { current, total in
                    Task { @MainActor in model.phase = .executing(current: current, total: total) }
                },
                isCancelled: { Task.isCancelled }
            )

            await MainActor.run {
                model.outcomes = results
                model.phase = .finished
                model.isShowingResults = true
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

    // MARK: - 되돌리기

    func restorableEntries() -> [RestoreService.Entry] {
        RestoreService(paths: paths).restorable()
    }

    /// 되돌린 뒤에는 목록이 바뀌었으므로 화면을 새로 그려야 한다.
    @discardableResult
    func restore(_ entry: RestoreService.Entry) -> RestoreService.Outcome {
        let outcome = RestoreService(paths: paths).restore(entry)
        objectWillChange.send()
        return outcome
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
#endif
