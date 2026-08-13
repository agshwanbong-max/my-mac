#if os(macOS)
import MacCleanCore
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
                    StorageBar(report: report)
                        .padding(Design.gutter)

                    ListHeader(report: report)

                    ForEach(model.visibleFindings) { finding in
                        FindingRow(finding: finding)
                        Divider().padding(.leading, 52)
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

// MARK: - 목록 머리말

private struct ListHeader: View {
    @EnvironmentObject private var model: AppModel
    let report: ScanReport

    var body: some View {
        HStack(spacing: 10) {
            Text(model.selectedCategory?.localizedTitle ?? "전체")
                .font(.title3.weight(.semibold))

            Text("\(model.visibleFindings.count)건")
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
                Button(model.allVisibleSelected ? "전체 해제" : "전체 선택") {
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

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text(model.selectedCategory == nil ? "정리할 게 없습니다" : "이 분류에는 항목이 없습니다")
                .font(.headline)
            Text("깨끗한 상태입니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 검사 중

private struct ScanningView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            ProgressView().controlSize(.small)

            Text(model.statusText.isEmpty ? "검사 중입니다…" : model.statusText)
                .font(.callout)
                .contentTransition(.opacity)

            Text("이 단계에서는 아무것도 지우지 않습니다. 읽기만 합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 건너뛴 항목

private struct WarningsBlock: View {
    let warnings: [ScanWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("검사 중 건너뛴 항목", systemImage: "info.circle")
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
                        Text("\(model.selectedFindings.count)건 선택 · \(ByteFormat.string(model.selectedBytes))")
                            .font(.callout.weight(.medium))
                            .contentTransition(.numericText())
                        Text(model.selectionIncludesIrreversible
                             ? "복구 불가 항목이 포함돼 있습니다"
                             : "선택한 항목은 휴지통으로 이동합니다")
                            .font(.caption)
                            .foregroundStyle(model.selectionIncludesIrreversible ? .orange : .secondary)
                    }
                }

                Spacer(minLength: 20)

                Button("미리보기") { model.performCleanup(dryRun: true) }
                    .secondaryAction()
                    .disabled(!model.canClean)

                Button("정리 실행") { model.requestCleanup() }
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
