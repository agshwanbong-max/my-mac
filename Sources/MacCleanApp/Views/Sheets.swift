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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("정리를 실행할까요?")
                    .font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(
                    icon: "trash",
                    tint: .accentColor,
                    title: "휴지통으로 이동 \(reversible.count)건",
                    subtitle: "\(ByteFormat.string(reversible.reduce(0) { $0 + $1.reclaimableBytes })) · 휴지통에서 되돌릴 수 있습니다."
                )

                if !irreversible.isEmpty {
                    summaryRow(
                        icon: "exclamationmark.triangle.fill",
                        tint: .red,
                        title: "완전 삭제 \(irreversible.count)건",
                        subtitle: "\(ByteFormat.string(irreversible.reduce(0) { $0 + $1.reclaimableBytes })) · 되돌릴 수 없습니다."
                    )
                }
            }

            if !irreversible.isEmpty {
                DisclosureGroup("완전 삭제되는 항목 보기") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(irreversible) { finding in
                                Text("· \(finding.title) — \(ByteFormat.string(finding.reclaimableBytes))")
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
                "휴지통으로 옮긴 항목은 휴지통을 비워야 실제 여유 공간이 늘어납니다.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button("미리보기만") { model.performCleanup(dryRun: true) }
                    .secondaryAction()
                Spacer()
                Button("취소") { model.isConfirming = false }
                    .secondaryAction()
                    .keyboardShortcut(.cancelAction)
                Button("실행") { model.performCleanup(dryRun: false) }
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
            Text(wasDryRun ? "미리보기 결과" : "정리 완료")
                .font(.title2.weight(.semibold))

            Text(wasDryRun
                ? "실제로는 아무것도 지우지 않았습니다. 확보 예상: \(ByteFormat.string(reclaimed))"
                : "확보: \(ByteFormat.string(reclaimed))")
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
                    "휴지통으로 옮긴 항목은 휴지통을 비워야 실제 여유 공간이 늘어납니다. 며칠 써보고 문제가 없을 때 비우세요.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Spacer()
                Button("다시 검사") {
                    model.isShowingResults = false
                    model.startScan()
                }
                .secondaryAction()
                Button("닫기") { model.isShowingResults = false }
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
