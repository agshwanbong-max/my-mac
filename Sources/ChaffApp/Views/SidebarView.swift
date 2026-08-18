#if os(macOS)
import AppKit
import ChaffCore
import SwiftUI

/// 카테고리 목록. 각 줄이 "여기서 얼마를 확보할 수 있는지"를 바로 말해준다.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            categoryList

            if !model.hasFullDiskAccess {
                Divider()
                PermissionNotice()
            }

            Divider()
            SupportFooter()
        }
        // 목록 첫 줄이 제목 줄 밑에 깔리는 것을 막는다. 사정은 아래에 적어 뒀다.
        .background(SidebarTopInset())
    }

    private var categoryList: some View {
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

/// 사이드바 목록이 제목 줄 아래에서 시작하게 만든다.
///
/// **왜 SwiftUI 로는 안 되는가**
/// `.listStyle(.sidebar)` 의 스크롤 뷰는 자기 틀 위로 넘어가서 그린다. macOS 26 의
/// 떠 있는 도구 막대 밑으로 내용이 흐르게 하려는 의도된 동작이고, 대신 스크롤 뷰가
/// 콘텐츠 인셋을 받아 첫 줄을 밀어내야 하는데 사이드바에는 그게 들어오지 않는다.
///
/// 위쪽에 여백을 주는 걸로는 고쳐지지 않는다. 여백은 **틀만** 줄이고 내용은 여전히
/// 창 꼭대기에서 그려져서, 첫 줄이 내려오는 게 아니라 잘려 나간다.
/// (여백을 크게 줬더니 목록이 통째로 사라진 것이 그 증거였다.)
///
/// 창에 물어봐도 소용없다. `contentLayoutRect` 도, 사이드바 칸의 좌표도 전부
/// "가려진 것 없음"이라고 답한다 — AppKit 기준으로는 그게 맞는 답이기 때문이다.
///
/// 그래서 macOS 가 이 일에 쓰는 장치를 직접 쓴다. 스크롤 뷰의 `contentInsets` 이다.
/// 이건 내용이 시작하는 자리를 옮기는 것이라, 잘라내지 않고 밀어낸다.
private struct SidebarTopInset: NSViewRepresentable {

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onGeometryChange = { [weak view] in
            guard let view else { return }
            apply(around: view)
        }
        apply(around: view)
    }

    private func apply(around view: ProbeView) {
        // 배치 도중에 스크롤 뷰를 건드리면 그 판이 어긋난다. 한 차례 미룬다.
        DispatchQueue.main.async {
            guard let window = view.window,
                  // 신호등 단추의 부모가 제목 줄 뷰다. 도구 막대까지 품고 있어서
                  // 필요한 높이가 여기서 정확히 나온다.
                  let titleBar = window.standardWindowButton(.closeButton)?.superview,
                  let scroll = sidebarScrollView(near: view)
            else { return }

            let wanted = titleBar.frame.height

            if ProcessInfo.processInfo.environment["CHAFF_LAYOUT_DEBUG"] != nil {
                let line = "[layout] 제목 줄 \(wanted)"
                    + " / 지금 인셋 \(scroll.contentInsets.top)"
                    + " / 자동조정 \(scroll.automaticallyAdjustsContentInsets)\n"
                FileHandle.standardError.write(Data(line.utf8))
            }

            // 이미 맞으면 손대지 않는다. 매번 건드리면 사용자가 스크롤한 위치를 빼앗는다.
            guard abs(scroll.contentInsets.top - wanted) > 0.5 else { return }

            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets(top: wanted, left: 0, bottom: 0, right: 0)

            // 인셋만 바꾸면 보이는 위치는 그대로다. 새로 생긴 위쪽까지 한 번 되감아야
            // 첫 줄이 실제로 내려온다.
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -wanted))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    /// 사이드바 목록의 스크롤 뷰를 찾는다.
    ///
    /// 이 뷰는 사이드바 칸의 배경으로 놓이므로, 조상을 한 단계씩 올라가며 그 아래에서
    /// 스크롤 뷰를 찾으면 가장 먼저 걸리는 것이 목록이다. 오른쪽 상세 칸까지 올라가기
    /// 전에 멈추므로 엉뚱한 스크롤 뷰를 잡지 않는다.
    private func sidebarScrollView(near view: NSView) -> NSScrollView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let found = firstScrollView(in: current) { return found }
            ancestor = current.superview
        }
        return nil
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scroll = subview as? NSScrollView { return scroll }
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    /// 창에 붙을 때와 배치가 바뀔 때마다 알려준다.
    /// `updateNSView` 만으로는 창 크기 변화를 놓친다 — SwiftUI 가 다시 그리지 않기 때문이다.
    final class ProbeView: NSView {
        var onGeometryChange: (() -> Void)?

        override func layout() {
            super.layout()
            onGeometryChange?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onGeometryChange?()
        }
    }
}
#endif
