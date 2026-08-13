#if os(macOS)
import MacCleanCore
import SwiftUI

/// 목록에 붙는 판정 딱지.
///
/// 이 앱에서 사용자가 가장 먼저 봐야 하는 것이다.
/// 예전에는 "안전 / 확인 필요 / 안내 전용" 을 보여줬는데, 그건 **앱의 정책**을 말한 것이지
/// 사용자가 알고 싶은 "그래서 지워도 되냐" 에 대한 대답이 아니었다.
struct VerdictBadge: View {
    let verdict: DeletionVerdict
    var compact = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: verdict.symbolName)
                .font(.caption2)
            Text(compact ? verdict.shortLabel : verdict.localizedTitle)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(verdict.tint.opacity(0.15))
        .foregroundStyle(verdict.tint)
        .clipShape(Capsule())
    }
}

/// 펼쳤을 때 보여주는 전체 판단 — 결론, 대가, 근거 순서.
struct AssessmentPanel: View {
    let assessment: ImportanceAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 결론이 맨 위. 나머지는 전부 이걸 뒷받침하는 것들이다.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: assessment.verdict.symbolName)
                    .foregroundStyle(assessment.verdict.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.verdict.localizedTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(assessment.verdict.tint)
                    Text(assessment.headline)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LabeledContent {
                Text(assessment.cost)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text("지우면")
                    .font(.caption.weight(.semibold))
            }

            HStack(spacing: 16) {
                chip("중요도", assessment.level.localizedTitle)
                chip("복구", assessment.recoverability.localizedTitle)
            }

            if !assessment.signals.isEmpty {
                DisclosureGroup("이렇게 판단한 근거 \(assessment.signals.count)가지") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(assessment.signals) { signal in
                            HStack(alignment: .top, spacing: 6) {
                                Text(arrow(for: signal.direction))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(color(for: signal.direction))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(signal.title)
                                        .font(.caption.weight(.medium))
                                    Text(signal.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                .font(.caption)
            }
        }
    }

    private func chip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
        .font(.caption)
    }

    private func arrow(for direction: ImportanceSignal.Direction) -> String {
        switch direction {
        case .raises: return "↑"
        case .lowers: return "↓"
        case .context: return "·"
        }
    }

    private func color(for direction: ImportanceSignal.Direction) -> Color {
        switch direction {
        case .raises: return .red
        case .lowers: return .green
        case .context: return .secondary
        }
    }
}
#endif
