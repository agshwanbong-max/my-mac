#if os(macOS)
import MacCleanCore
import SwiftUI

/// 디스크 전체를 한 줄로 보여준다.
///
/// macOS 저장 공간 설정과 같은 시각 언어를 쓴다 — 익숙한 형태라 설명이 필요 없다.
/// 다만 여기서는 **정리 가능한 부분만 색으로 뜯어낸다.**
/// 회색(그냥 사용 중) 옆에 색 조각이 붙어 있으면, 그게 오늘 되찾을 수 있는 몫이다.
struct StorageBar: View {
    let report: ScanReport

    private var totalCapacity: Int64 { max(report.volume.totalCapacity, 1) }
    private var used: Int64 { max(0, report.volume.totalCapacity - report.volume.availableCapacity) }
    private var reclaimable: Int64 { min(report.totalReclaimable, used) }
    /// 정리 대상이 아닌 사용 중 공간.
    private var occupied: Int64 { max(0, used - reclaimable) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GeometryReader { geometry in
                let width = geometry.size.width

                HStack(spacing: 1.5) {
                    segment(color: Color.secondary.opacity(0.35), bytes: occupied, width: width)

                    ForEach(report.categoryTotals) { entry in
                        segment(color: entry.category.tint, bytes: entry.bytes, width: width)
                    }

                    // 남는 공간은 빈 트랙이 채운다.
                    RoundedRectangle(cornerRadius: Design.barRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                }
            }
            .frame(height: 14)

            legend
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: Design.panelRadius, style: .continuous))
    }

    // MARK: -

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ByteFormat.string(report.volume.availableCapacity))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(L("storage.freeOfTotal", ByteFormat.string(report.volume.totalCapacity)))
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            if report.totalReclaimable > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                    Text(L("storage.reclaimable", ByteFormat.string(report.totalReclaimable)))
                        .font(.callout.weight(.medium))
                }
            }
        }
    }

    private func segment(color: Color, bytes: Int64, width: CGFloat) -> some View {
        let ratio = Double(bytes) / Double(totalCapacity)
        // 아주 작은 조각도 최소 3pt 는 보이게 해서, 있는데 안 보이는 일이 없게 한다.
        let raw = width * ratio
        let segmentWidth = bytes > 0 ? max(3, raw) : 0

        return RoundedRectangle(cornerRadius: Design.barRadius, style: .continuous)
            .fill(color)
            .frame(width: segmentWidth)
    }

    @ViewBuilder
    private var legend: some View {
        let entries = report.categoryTotals.prefix(6)

        if entries.isEmpty {
            Text(L("storage.nothingFound"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // 창 폭에 따라 자동으로 줄바꿈된다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legendItems(entries) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) { legendItems(entries.prefix(3)) }
                    HStack(spacing: 14) { legendItems(entries.dropFirst(3)) }
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func legendItems(_ entries: ArraySlice<CategoryTotal>) -> some View {
        ForEach(Array(entries)) { entry in
            HStack(spacing: 5) {
                Circle()
                    .fill(entry.category.tint)
                    .frame(width: 7, height: 7)
                Text(entry.category.localizedTitle)
                    .foregroundStyle(.secondary)
                Text(ByteFormat.string(entry.bytes))
                    .monospacedDigit()
            }
        }
    }
}
#endif
