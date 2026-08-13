#if os(macOS)
import MacCleanCore
import SwiftUI

struct FindingRow: View {
    @EnvironmentObject private var model: AppModel
    let finding: Finding

    @State private var isExpanded = false

    private var isSelected: Bool { model.selection.contains(finding.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                checkbox

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(finding.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        RiskBadge(risk: finding.risk)
                        if !finding.removal.isReversible && finding.isSelectable {
                            Label("복구 불가", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    Text(finding.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if finding.reclaimableBytes > 0 {
                    Text(ByteFormat.string(finding.reclaimableBytes))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(finding.isSelectable ? .primary : .secondary)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("지우면 무슨 일이 생기는지 보기")
            }

            if isExpanded {
                details
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(finding) }
        .contextMenu {
            if finding.path != nil {
                Button("파인더에서 보기") { model.revealInFinder(finding) }
                Button("경로 복사") { model.copyToPasteboard(finding.path?.path ?? "") }
            }
            if let command = finding.suggestedCommand {
                Button("명령어 복사") { model.copyToPasteboard(command) }
            }
        }
    }

    @ViewBuilder
    private var checkbox: some View {
        if finding.isSelectable {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .onTapGesture { model.toggle(finding) }
        } else {
            Image(systemName: "info.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .help("안내 전용 — 이 앱은 이 항목을 건드리지 않습니다")
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let path = finding.path {
                LabeledContent("경로") {
                    Text(path.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            LabeledContent("지우면") {
                Text(finding.consequence)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent("처리 방식") {
                Text(finding.removal.localizedTitle)
                    .font(.caption)
            }

            if finding.itemCount > 0 {
                LabeledContent("포함 항목") {
                    Text("\(finding.itemCount)개")
                        .font(.caption)
                }
            }

            if let command = finding.suggestedCommand {
                VStack(alignment: .leading, spacing: 4) {
                    Text("직접 실행할 명령")
                        .font(.caption.weight(.semibold))
                    HStack(alignment: .top) {
                        Text(command)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Button("복사") { model.copyToPasteboard(command) }
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.leading, 32)
        .padding(.top, 2)
        .foregroundStyle(.secondary)
    }
}

struct RiskBadge: View {
    let risk: RiskLevel

    private var color: Color {
        switch risk {
        case .safe: return .green
        case .review: return .orange
        case .advisory: return .secondary
        }
    }

    var body: some View {
        Text(risk.localizedTitle)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .help(risk.localizedExplanation)
    }
}
#endif
