#if os(macOS)
import MacCleanCore
import SwiftUI

/// 실행 전 마지막 확인.
///
/// 보수적 정책의 핵심 장치다. 여기서 사용자는 세 가지를 반드시 본다.
/// 1. 몇 건이 어디로 가는지
/// 2. 되돌릴 수 없는 항목이 몇 건인지
/// 3. 휴지통을 비워야 실제로 용량이 는다는 사실
struct ConfirmSheet: View {
    @EnvironmentObject private var model: AppModel

    private var reversible: [Finding] { model.selectedFindings.filter { $0.removal.isReversible } }
    private var irreversible: [Finding] { model.selectedFindings.filter { !$0.removal.isReversible } }
    /// 탐색기에서 직접 고른 항목. 규칙이 검증하지 않은 경로라 따로 알려야 한다.
    private var manual: [Finding] { model.selectedFindings.filter { $0.category == .manualSelection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(L("confirm.title"))
                    .font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(
                    icon: "trash",
                    tint: .accentColor,
                    title: L("confirm.toTrash", reversible.count),
                    subtitle: L("confirm.toTrash.detail", ByteFormat.string(reversible.reduce(0) { $0 + $1.reclaimableBytes }))
                )

                if !irreversible.isEmpty {
                    summaryRow(
                        icon: "exclamationmark.triangle.fill",
                        tint: .red,
                        title: L("confirm.permanent", irreversible.count),
                        subtitle: L("confirm.permanent.detail", ByteFormat.string(irreversible.reduce(0) { $0 + $1.reclaimableBytes }))
                    )
                }

                if !manual.isEmpty {
                    summaryRow(
                        icon: "hand.point.up.left.fill",
                        tint: .orange,
                        title: L("confirm.manual", manual.count),
                        subtitle: L("confirm.manual.detail", ByteFormat.string(manual.reduce(0) { $0 + $1.reclaimableBytes }))
                    )
                }
            }

            if !irreversible.isEmpty {
                DisclosureGroup(L("confirm.showPermanentList")) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(irreversible) { finding in
                                Text(L("confirm.listItem", finding.title, ByteFormat.string(finding.reclaimableBytes)))
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
                .font(.callout)
            }

            Label(
                L("confirm.emptyTrashNote"),
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button(L("confirm.previewOnly")) { model.performCleanup(dryRun: true) }
                    .secondaryAction()
                Spacer()
                Button(L("common.cancel")) { model.isConfirming = false }
                    .secondaryAction()
                    .keyboardShortcut(.cancelAction)
                Button(L("confirm.run")) { model.performCleanup(dryRun: false) }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func summaryRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 실행 결과.
struct ResultsSheet: View {
    @EnvironmentObject private var model: AppModel

    private var reclaimed: Int64 {
        model.outcomes
            .filter { $0.status == .removed || $0.status == .deleted || $0.status == .simulated }
            .reduce(0) { $0 + $1.bytes }
    }

    private var wasDryRun: Bool {
        model.outcomes.contains { $0.status == .simulated }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(wasDryRun ? L("results.dryRun.title") : L("results.done.title"))
                .font(.title2.weight(.semibold))

            Text(wasDryRun
                ? L("results.dryRun.detail", ByteFormat.string(reclaimed))
                : L("results.done.detail", ByteFormat.string(reclaimed)))
                .font(.callout)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.outcomes) { outcome in
                        HStack(alignment: .top, spacing: 8) {
                            statusIcon(outcome.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(outcome.finding.title)
                                    .font(.callout)
                                Text(outcome.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)

            if !wasDryRun {
                Label(
                    L("results.emptyTrashNote"),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Spacer()
                Button(L("action.rescan")) {
                    model.isShowingResults = false
                    model.startScan()
                }
                .secondaryAction()
                Button(L("common.close")) { model.isShowingResults = false }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    @ViewBuilder
    private func statusIcon(_ status: CleanupOutcome.Status) -> some View {
        switch status {
        case .removed, .deleted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .simulated:
            Image(systemName: "eye").foregroundStyle(.secondary)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
#endif
