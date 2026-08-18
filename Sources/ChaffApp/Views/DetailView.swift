#if os(macOS)
import ChaffCore
import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            content

            // 액션 바는 목록 위에 떠 있는다. 목록이 아무리 길어도 항상 손에 닿는다.
            if model.report != nil {
                ActionBar()
                    .padding(Design.gutter)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.selectedCategory)
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .scanning && model.report == nil {
            ScanningView()
        } else if let report = model.report {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 다시 검사할 때도 이전 결과를 지우지 않는다. 막대만 위에 얹는다.
                    if model.phase == .scanning {
                        ScanProgressBar()
                            .padding(.horizontal, Design.gutter)
                            .padding(.top, Design.gutter)
                    }

                    StorageBar(report: report)
                        .padding(Design.gutter)

                    if model.selectedCategory == nil {
                        // "전체" 는 분류별로 묶어서 보여준다. 평평한 목록으로는 뭐가 뭔지 알 수 없다.
                        ForEach(report.categoriesInOrder, id: \.self) { category in
                            CategoryBlock(category: category, findings: report.findings(in: category))
                        }
                    } else {
                        ListHeader(report: report)
                        ForEach(model.visibleFindings) { finding in
                            FindingRow(finding: finding)
                            Divider().padding(.leading, 52)
                        }
                    }

                    if model.visibleFindings.isEmpty {
                        EmptyStateView()
                    }

                    if model.selectedCategory == nil && !report.warnings.isEmpty {
                        WarningsBlock(warnings: report.warnings)
                    }

                    // 떠 있는 액션 바에 가리지 않도록 아래 여백을 준다.
                    Color.clear.frame(height: 88)
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            ScanningView()
        }
    }
}

// MARK: - 진행 막대

/// 검사 진행 상황.
///
/// 스캐너 단위로 센다. 동시에 도는 스캐너들의 "지금 몇 %" 를 정확히 말할 방법이 없어서
/// **끝난 개수**를 세는 쪽을 택했다 — 거짓 없는 숫자다.
/// 대신 아래 줄에 오래 걸리는 스캐너가 흘려보내는 상세 진행이 계속 갱신된다.
struct ScanProgressBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L("scan.running"))
                    .font(.callout.weight(.medium))

                Text("\(model.scanProgress.completed) / \(model.scanProgress.total)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())

                Spacer()

                Button(L("scan.stop")) { model.cancelScan() }
                    .controlSize(.small)
            }

            ProgressView(value: model.scanProgress.fraction)
                .progressViewStyle(.linear)

            Text(model.statusText.isEmpty ? L("scan.readOnlyNotice") : model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: model.scanProgress)
    }
}

// MARK: - 분류 묶음 ("전체" 화면에서만 쓴다)

private struct CategoryBlock: View {
    @EnvironmentObject private var model: AppModel
    let category: FindingCategory
    let findings: [Finding]

    var body: some View {
        let reclaimable = findings.filter { $0.isSelectable }.reduce(Int64(0)) { $0 + $1.reclaimableBytes }

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: category.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(category.tint)
                Text(category.localizedTitle)
                    .font(.headline)
                Text(L("common.itemCount", findings.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if reclaimable > 0 {
                    Text(ByteFormat.string(reclaimable))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button(L("detail.showOnlyCategory")) { model.sidebarSelection = .category(category) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .padding(.horizontal, Design.gutter)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ForEach(findings) { finding in
                FindingRow(finding: finding)
                Divider().padding(.leading, 52)
            }
        }
    }
}

// MARK: - 목록 머리말

private struct ListHeader: View {
    @EnvironmentObject private var model: AppModel
    let report: ScanReport

    var body: some View {
        HStack(spacing: 10) {
            Text(model.selectedCategory?.localizedTitle ?? L("sidebar.all"))
                .font(.title3.weight(.semibold))

            Text(L("common.itemCount", model.visibleFindings.count))
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            if model.phase == .scanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if model.visibleSelectableCount > 0 {
                Button(model.allVisibleSelected ? L("detail.deselectAll") : L("detail.selectAll")) {
                    model.setSelectionForVisible(!model.allVisibleSelected)
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
        .padding(.horizontal, Design.gutter)
        .padding(.bottom, 10)
    }
}

// MARK: - 빈 상태

private struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel

    /// 시스템 데이터·용량 분포는 정밀 분석을 켜야만 나온다.
    /// 그걸 모르면 "조회가 안 된다" 로만 보인다. 그래서 이유와 버튼을 같이 준다.
    private var needsDeepScan: Bool {
        guard let category = model.selectedCategory else { return false }
        return (category == .systemData || category == .spaceBreakdown) && !model.includeDeepScan
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: needsDeepScan ? "chart.pie" : "sparkles")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            if needsDeepScan {
                Text(L("detail.deepScanRequired.title"))
                    .font(.headline)
                Text("""
                    시스템 데이터가 무엇으로 채워져 있는지 알려면 홈 전체를 훑어야 합니다. \
                    파일 수에 따라 20~40초 걸립니다. 읽기만 하고 아무것도 지우지 않습니다.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)

                Button(L("detail.deepScanRequired.action")) {
                    model.includeDeepScan = true
                    model.startScan()
                }
                .primaryAction()
                .disabled(model.isBusy)
            } else {
                Text(model.selectedCategory == nil ? L("detail.empty.all") : L("detail.empty.category"))
                    .font(.headline)
                Text(L("detail.empty.detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 검사 중

private struct ScanningView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            ScanProgressBar()
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Design.gutter)
    }
}

// MARK: - 건너뛴 항목

private struct WarningsBlock: View {
    let warnings: [ScanWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("detail.skipped.title"), systemImage: "info.circle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(warnings) { warning in
                Text(warning.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(Design.gutter)
    }
}

// MARK: - 떠 있는 액션 바

private struct ActionBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GlassGroup {
            HStack(spacing: 14) {
                if case .executing(let current, let total) = model.phase {
                    ProgressView(value: Double(current), total: Double(max(total, 1)))
                        .frame(width: 150)
                    Text("\(current) / \(total)")
                        .font(.callout.monospacedDigit())
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("action.selectionSummary", model.selectedFindings.count, ByteFormat.string(model.selectedBytes)))
                            .font(.callout.weight(.medium))
                            .contentTransition(.numericText())
                        Text(model.selectionIncludesIrreversible
                             ? L("action.containsPermanent")
                             : L("action.movesToTrash"))
                            .font(.caption)
                            .foregroundStyle(model.selectionIncludesIrreversible ? .orange : .secondary)
                    }
                }

                Spacer(minLength: 20)

                Button(L("action.preview")) { model.performCleanup(dryRun: true) }
                    .secondaryAction()
                    .disabled(!model.canClean)

                Button(L("action.clean")) { model.requestCleanup() }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canClean)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassPanel()
        }
        .animation(.easeInOut(duration: 0.2), value: model.selectedBytes)
    }
}
#endif
