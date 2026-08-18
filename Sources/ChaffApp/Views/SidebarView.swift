#if os(macOS)
import AppKit
import ChaffCore
import SwiftUI

/// 카테고리 목록. 각 줄이 "여기서 얼마를 확보할 수 있는지"를 바로 말해준다.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section {
                row(
                    title: L("sidebar.all"),
                    symbol: "square.grid.2x2",
                    tint: .accentColor,
                    bytes: model.report?.totalReclaimable ?? 0,
                    count: model.report?.findings.count ?? 0
                )
                .tag(AppModel.SidebarItem.all)

                // 데이터가 없어도 항상 띄운다.
                // 줄 자체가 없으면 "시스템 데이터를 어디서 보나" 를 알 길이 없다.
                // 눌렀을 때 정밀 분석을 켜라고 안내하는 편이 낫다.
                row(
                    title: FindingCategory.systemData.localizedTitle,
                    symbol: FindingCategory.systemData.symbolName,
                    tint: FindingCategory.systemData.tint,
                    bytes: 0,
                    count: model.report?.findings(in: .systemData).count ?? 0
                )
                .tag(AppModel.SidebarItem.category(.systemData))
            }

            if let report = model.report, !report.categoriesInOrder.isEmpty {
                Section(L("sidebar.categories")) {
                    // 시스템 데이터는 위 고정 자리에 이미 있다.
                    ForEach(report.categoriesInOrder.filter { $0 != .systemData }, id: \.self) { category in
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
            VStack(spacing: 0) {
                if !model.hasFullDiskAccess {
                    PermissionNotice()
                }
                SupportFooter()
            }
        }
        .background(LayoutReport())
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

/// 사이드바 맨 아래에 **항상** 있다.
///
/// 메뉴 막대에도 후원하기가 있지만, 맥 앱의 메뉴 막대는 찾아 들어가는 사람만 본다.
/// 무료로 쓰다가 문득 고마워지는 순간은 검사 결과를 볼 때인데, 그때 눈에 보이는 곳은 여기다.
///
/// 대신 조용해야 한다. 배지도, 색도, 강조도 없다 —
/// 정리하러 온 사람을 붙잡고 돈 얘기를 하면 그게 광고다.
private struct SupportFooter: View {
    var body: some View {
        Link(destination: SupportLinks.support) {
            HStack(spacing: 6) {
                Image(systemName: "heart")
                Text(L("menu.support"))
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("menu.support.help"))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

/// 전체 디스크 접근 권한이 없을 때만 사이드바 아래에 붙는다.
private struct PermissionNotice: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("permission.partial.title"), systemImage: "lock.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text(L("permission.partial.detail"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(L("permission.openSettings")) { model.openFullDiskAccessSettings() }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
    }
}

/// 사이드바 목록이 어디에 어떻게 놓였는지 그대로 받아 적는다. 화면은 바꾸지 않는다.
///
/// 첫 줄이 제목 줄 밑에 깔려 보이는 문제를 다섯 번 고치려다 다섯 번 빗나갔다.
/// 전부 화면을 눈으로 보고 원인을 짐작해서 손댄 것이었다. 그러다 한국어에서는
/// 멀쩡하다는 사실이 나왔고, 그러면 제목 줄이나 안전 영역 문제일 수가 없다.
///
/// 그래서 고치기 전에 재기부터 한다. 두 언어를 같은 자로 재서 다른 값을 찾는다.
///
///     CHAFF_LAYOUT_DEBUG=1 build/Chaff.app/Contents/MacOS/Chaff
///
private struct LayoutReport: NSViewRepresentable {

    func makeNSView(context: Context) -> ReportView { ReportView() }

    func updateNSView(_ view: ReportView, context: Context) {
        view.onGeometryChange = { [weak view] in
            guard let view else { return }
            report(around: view)
        }
        report(around: view)
    }

    private func report(around view: ReportView) {
        guard ProcessInfo.processInfo.environment["CHAFF_LAYOUT_DEBUG"] != nil else { return }

        DispatchQueue.main.async {
            guard let window = view.window else { return }

            var lines = ["", "── 사이드바 측정 ──"]
            lines.append("언어: \(L10n.currentLanguage)")
            lines.append("창 높이: \(window.frame.height)")

            if let titleBar = window.standardWindowButton(.closeButton)?.superview {
                lines.append("제목 줄 높이: \(titleBar.frame.height)")
            }

            let mine = view.convert(view.bounds, to: nil)
            lines.append("사이드바 칸: 위 \(mine.maxY) 아래 \(mine.minY) 높이 \(mine.height)")

            if let scroll = firstScrollView(near: view) {
                let visible = scroll.documentVisibleRect
                lines.append("스크롤 뷰 높이: \(scroll.frame.height)")
                lines.append("콘텐츠 인셋 위: \(scroll.contentInsets.top) (자동조정 \(scroll.automaticallyAdjustsContentInsets))")
                lines.append("보이는 구간: y \(visible.minY) ~ \(visible.maxY)")
                if let document = scroll.documentView {
                    lines.append("내용 높이: \(document.frame.height)")
                    lines.append("내용이 뷰포트보다 큰가: \(document.frame.height > visible.height)")
                }
            } else {
                lines.append("스크롤 뷰: 못 찾음")
            }

            FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        }
    }

    private func firstScrollView(near view: NSView) -> NSScrollView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let found = descendantScrollView(in: current) { return found }
            ancestor = current.superview
        }
        return nil
    }

    private func descendantScrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scroll = subview as? NSScrollView { return scroll }
            if let found = descendantScrollView(in: subview) { return found }
        }
        return nil
    }

    final class ReportView: NSView {
        var onGeometryChange: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onGeometryChange?()
        }
    }
}
#endif
