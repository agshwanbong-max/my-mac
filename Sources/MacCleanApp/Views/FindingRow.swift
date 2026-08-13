#if os(macOS)
import MacCleanCore
import SwiftUI

/// 항목 한 줄.
///
/// 기본 상태는 최대한 조용하게 — 이름, 크기, 등급 점 하나.
/// "지우면 어떻게 되는지"는 펼쳤을 때만 나온다. 목록이 설명으로 뒤덮이지 않게 하려는 것이다.
struct FindingRow: View {
    @EnvironmentObject private var model: AppModel
    let finding: Finding

    @State private var isExpanded = false
    @State private var isHovering = false
    /// 안내 전용 항목은 규칙이 판정을 갖고 있지 않다. 펼칠 때 그 경로를 실제로 조사해서 답한다.
    /// 검사할 때 전부 미리 돌리지 않는 이유는, 그러면 검사가 느려지기 때문이다.
    @State private var assessment: ImportanceAssessment?
    @State private var isAssessing = false

    private var isSelected: Bool { model.isSelected(finding) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                marker

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(finding.title)
                            .font(.body)
                            .lineLimit(1)

                        // 판정이 제목 바로 옆에 온다. 사용자가 알고 싶은 건 이것 하나다.
                        if let verdict = finding.presetVerdict ?? assessment?.verdict {
                            VerdictBadge(verdict: verdict)
                        } else if isAssessing {
                            VerdictPlaceholder()
                        }

                        if !finding.removal.isReversible && finding.isSelectable {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .help("복구할 수 없습니다")
                        }
                    }

                    Text(finding.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if finding.reclaimableBytes > 0 {
                    Text(ByteFormat.string(finding.reclaimableBytes))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(finding.isSelectable ? .primary : .secondary)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    if isExpanded { assessIfNeeded() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isExpanded ? 1 : 0.35)
                .help("자세히 보기")
            }
            .padding(.horizontal, Design.gutter)
            .padding(.vertical, 10)

            if isExpanded {
                details
                    .padding(.horizontal, Design.gutter)
                    .padding(.bottom, 12)
            }
        }
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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

    // MARK: - 선택 표시

    @ViewBuilder
    private var marker: some View {
        if finding.isSelectable {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 18, height: 18)
            .animation(.easeInOut(duration: 0.12), value: isSelected)
            .onTapGesture { model.toggle(finding) }
        } else {
            // 안내 전용 — 체크박스 자리에 등급 아이콘만 둔다. 애초에 고를 수 없다는 뜻이다.
            Image(systemName: "info.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .help("안내 전용 — 이 앱은 이 항목을 건드리지 않습니다")
        }
    }

    // MARK: - 펼친 내용

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 경로를 실제로 조사한 결과가 있으면 그게 먼저다. 규칙 설명보다 구체적이다.
            if let assessment {
                AssessmentPanel(assessment: assessment)
                Divider()
            }

            infoLine(label: "지우면", value: finding.consequence, tint: finding.risk.tint)

            HStack(spacing: 20) {
                infoChip(label: "등급", value: finding.risk.localizedTitle, tint: finding.risk.tint)
                infoChip(label: "처리", value: finding.removal.localizedTitle, tint: .secondary)
                if finding.itemCount > 0 {
                    infoChip(label: "항목", value: "\(finding.itemCount)개", tint: .secondary)
                }
            }

            if let path = finding.path {
                Text(path.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let command = finding.suggestedCommand {
                HStack(alignment: .top, spacing: 8) {
                    Text(command)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        model.copyToPasteboard(command)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("명령어 복사")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.leading, 30)
    }

    /// 판정이 없는 항목만 조사한다. 한 번 조사하면 다시 하지 않는다.
    private func assessIfNeeded() {
        guard assessment == nil, !isAssessing, let path = finding.path else { return }
        isAssessing = true

        Task.detached(priority: .userInitiated) {
            let result = ImportanceAssessor(paths: UserPaths.current()).assess(path)
            await MainActor.run {
                assessment = result
                isAssessing = false
            }
        }
    }

    private func infoLine(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoChip(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(tint)
        }
        .font(.caption)
    }
}
#endif
