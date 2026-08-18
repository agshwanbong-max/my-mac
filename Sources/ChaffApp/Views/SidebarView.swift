#if os(macOS)
import AppKit
import ChaffCore
import SwiftUI

/// 카테고리 목록. 각 줄이 "여기서 얼마를 확보할 수 있는지"를 바로 말해준다.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    /// 사이드바 위쪽이 제목 줄에 가려진 높이. `TitleBarProbe` 가 채워 준다.
    ///
    /// macOS 26 에서 NavigationSplitView 의 사이드바가 제목 줄만큼의 안전 영역을
    /// 못 받는 일이 있다. 그러면 목록이 창 맨 위에서 시작해 첫 줄이 신호등 단추에
    /// 가리고, 붙박이 구역 머리글이 그 위에 겹쳐 찍힌다. 항목이 몇 개 없으면
    /// 스크롤도 안 되니 가려진 첫 줄에 아예 손이 닿지 않는다.
    ///
    /// macOS 가 제대로 밀어주면 이 값은 0 이 되고 보정도 저절로 사라진다.
    @State private var hiddenUnderTitleBar: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            categoryList
                .padding(.top, hiddenUnderTitleBar)

            if !model.hasFullDiskAccess {
                Divider()
                PermissionNotice()
            }

            Divider()
            SupportFooter()
        }
        // 재는 자는 바깥에 둔다. 안쪽 여백을 바꿔도 이 뷰의 위치는 그대로여서
        // 여백과 측정이 서로를 물고 늘어지지 않는다.
        .background(TitleBarProbe(hidden: $hiddenUnderTitleBar))
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

/// 사이드바 위쪽이 제목 줄에 얼마나 가려졌는지 창에 직접 물어보는, 보이지 않는 자.
///
/// SwiftUI 좌표 공간으로는 이 질문에 답할 수 없다. 어느 조상 뷰를 기준으로 재느냐에 따라
/// 값이 달라지는데, 정작 알아야 하는 건 **창 자체**와의 관계이기 때문이다.
///
/// `contentLayoutRect` 로는 안 된다. macOS 26 의 떠 있는 도구 막대는 콘텐츠가 그 밑으로
/// 흐르는 것을 정상으로 보기 때문에, 창은 "가려진 것 없음"이라고 답한다.
///
/// 그래서 제목 줄 **뷰 자체**를 기준으로 잰다. 신호등 단추가 얹혀 있는 그 뷰다.
/// 사이드바의 위쪽 끝이 그 뷰의 아래 모서리보다 얼마나 올라가 있는지가 곧 겹친 높이다.
/// 순수한 기하 계산이라 도구 막대 모양이나 창 크기가 바뀌어도, 전체 화면으로 들어가
/// 제목 줄이 사라져도 그대로 따라간다.
private struct TitleBarProbe: NSViewRepresentable {
    @Binding var hidden: CGFloat

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        // 여기서 매번 다시 매단다. 그래야 콜백이 낡은 바인딩을 붙잡고 있지 않는다.
        // 뷰를 약하게 잡아야 뷰와 콜백이 서로를 붙들고 안 놓아주는 일이 없다.
        view.onGeometryChange = { [weak view] in
            guard let view else { return }
            measure(view)
        }
        measure(view)
    }

    private func measure(_ view: ProbeView) {
        // 배치 도중에 상태를 건드리면 SwiftUI 가 같은 판을 다시 그린다. 한 차례 미룬다.
        DispatchQueue.main.async {
            guard let window = view.window,
                  // 신호등 단추의 부모가 제목 줄 뷰다. 도구 막대까지 품고 있어서
                  // 높이는 여기서 정확히 나온다. 다만 이 뷰는 콘텐츠 뷰와 다른 가지에 있어서
                  // 좌표를 직접 변환하면 안 된다 — 조용히 0 이 나온다.
                  let titleBar = window.standardWindowButton(.closeButton)?.superview
            else { return }

            let titleBarHeight = titleBar.frame.height

            // 창 좌표로 옮겨 놓고 높이끼리만 비교한다. macOS 는 y 가 위로 자란다.
            // 창 꼭대기에서 제목 줄 높이만큼 내려온 지점이 사이드바가 시작해도 되는 곳이다.
            let myTop = view.convert(view.bounds, to: nil).maxY
            let allowedTop = window.frame.height - titleBarHeight

            let overlap = max(0, myTop - allowedTop)

            // macOS 26 부터 도구 막대는 콘텐츠 **위에 떠서** 그려진다.
            // 그래서 창은 "가려진 것 없음"이라고 답한다 — AppKit 기준으로는 그게 맞다.
            // 콘텐츠가 그 밑으로 흐르는 게 의도이고, 대신 스크롤 뷰가 콘텐츠 인셋을 받아
            // 첫 줄을 밀어내야 한다. 사이드바 목록에는 그 인셋이 들어오지 않는다.
            //
            // 재서는 잡을 수 없는 종류다. 창의 좌표는 전부 정상이라고 말하는데
            // 눈에만 가려 보인다. 그래서 이 버전대에서는 제목 줄 높이를 바닥값으로 깐다.
            let floatingToolbar = ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
            )

            // 보정은 제목 줄 높이를 넘을 수 없다. 이 못이 없으면 계산이 어긋났을 때
            // 목록이 통째로 화면 밖으로 밀려나 사이드바가 텅 빈 것처럼 보인다.
            let measured = min(max(overlap, floatingToolbar ? titleBarHeight : 0), titleBarHeight)

            // 이 보정은 눈으로만 확인할 수 있어서, 빗나갔을 때 원인을 좁힐 방법이 필요하다.
            // 켤 때만 숫자를 흘린다: CHAFF_LAYOUT_DEBUG=1 Chaff.app/Contents/MacOS/Chaff
            if ProcessInfo.processInfo.environment["CHAFF_LAYOUT_DEBUG"] != nil {
                let line = "[layout] 창 높이 \(window.frame.height)"
                    + " / 제목 줄 높이 \(titleBarHeight)"
                    + " / 사이드바 위 \(myTop)"
                    + " / 시작해도 되는 높이 \(allowedTop)"
                    + " / 겹침 \(overlap)"
                    + " / 떠 있는 도구 막대 \(floatingToolbar)"
                    + " → 보정 \(measured)\n"
                FileHandle.standardError.write(Data(line.utf8))
            }

            // 소수점 떨림으로 다시 그리지 않게 한다.
            if abs(measured - hidden) > 0.5 { hidden = measured }
        }
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
