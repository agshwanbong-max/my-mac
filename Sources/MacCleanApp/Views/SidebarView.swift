#if os(macOS)
import MacCleanCore
import SwiftUI

/// 카테고리 목록. 각 줄이 "여기서 얼마를 확보할 수 있는지"를 바로 말해준다.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section {
                row(
                    title: "전체",
                    symbol: "square.grid.2x2",
                    tint: .accentColor,
                    bytes: model.report?.totalReclaimable ?? 0,
                    count: model.report?.findings.count ?? 0
                )
                .tag(AppModel.SidebarItem.all)
            }

            if let report = model.report, !report.categoriesInOrder.isEmpty {
                Section("분류") {
                    ForEach(report.categoriesInOrder, id: \.self) { category in
                        row(
                            title: category.localizedTitle,
                            symbol: category.symbolName,
                            tint: category.tint,
                            bytes: report.reclaimable(in: category),
                            count: report.findings(in: category).count
                        )
                        .tag(AppModel.SidebarItem.category(category))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if !model.hasFullDiskAccess {
                PermissionNotice()
            }
        }
    }

    private func row(title: String, symbol: String, tint: Color, bytes: Int64, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 20)

            Text(title)
                .lineLimit(1)

            Spacer(minLength: 6)

            if bytes > 0 {
                Text(ByteFormat.string(bytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 전체 디스크 접근 권한이 없을 때만 사이드바 아래에 붙는다.
private struct PermissionNotice: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("일부 항목을 못 봅니다", systemImage: "lock.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text("기기 백업, 메일 첨부, 샌드박스 앱 캐시는 전체 디스크 접근 권한이 있어야 보입니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("설정 열기") { model.openFullDiskAccessSettings() }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
    }
}
#endif
