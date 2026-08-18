#if os(macOS)
import AppKit
import MacCleanCore
import SwiftUI

/// 첫 실행 안내.
///
/// 웹으로 배포하면 여기가 가장 큰 이탈 지점이다.
/// 권한 없이 앱이 열리면 "아무것도 못 찾네" 하고 지워버린다.
/// 배너로 알리는 것만으로는 부족하다 — 이미 결과 화면을 본 뒤라 늦다.
///
/// 그래서 검사를 시작하기 **전에** 세 가지를 말한다.
/// 1. 이 앱이 무엇을 하는가
/// 2. 왜 전체 디스크 접근이 필요한가 (권한을 달라고만 하면 아무도 안 준다)
/// 3. 무엇을 하지 않는가 (파일을 지우는 앱이 신뢰를 얻는 유일한 방법)
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    @State private var hasAccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(
                        icon: "chart.pie",
                        tint: .blue,
                        title: L("onboarding.what.title"),
                        body: L("onboarding.what.body")
                    )

                    permissionSection

                    section(
                        icon: "hand.raised.fill",
                        tint: .green,
                        title: L("onboarding.never.title"),
                        body: L("onboarding.never.body")
                    )
                }
                .padding(28)
            }

            Divider()
            footer
        }
        .frame(width: 620, height: 620)
        .onAppear { refresh() }
        // 설정 앱에 다녀오면 권한이 바뀌어 있을 수 있다. 돌아오는 순간 다시 확인한다.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    // MARK: -

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "internaldrive")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("MacClean")
                    .font(.title2.weight(.semibold))
                Text(L("onboarding.tagline"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(28)
    }

    /// 권한 요청은 "왜 필요한지" 와 "지금 상태" 를 같이 보여줘야 한다.
    /// 둘 중 하나만 있으면 사용자는 움직이지 않는다.
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(
                icon: hasAccess ? "checkmark.shield.fill" : "lock.shield",
                tint: hasAccess ? .green : .orange,
                title: hasAccess ? L("onboarding.access.on.title") : L("onboarding.access.off.title"),
                body: hasAccess
                    ? L("onboarding.access.on.body")
                    : L("onboarding.access.off.body")
            )

            if !hasAccess {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        model.openFullDiskAccessSettings()
                    } label: {
                        Label(L("onboarding.access.openSettings"), systemImage: "arrow.up.forward.app")
                    }
                    .primaryAction()

                    Text(L("onboarding.access.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 38)
            }
        }
    }

    private func section(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Link(L("menu.sourceCode"), destination: SupportLinks.repository)
                .font(.caption)
            Link(L("menu.support"), destination: SupportLinks.support)
                .font(.caption)

            Spacer()

            // 권한 없이도 시작할 수 있어야 한다. 강제하면 앱을 닫아버린다.
            // 대신 그 상태로는 절반만 찾는다는 걸 알고 시작하게 만든다.
            Button(hasAccess ? L("onboarding.start") : L("onboarding.startWithout")) {
                model.completeOnboarding()
            }
            .primaryAction()
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func refresh() {
        hasAccess = FullDiskAccessProbe.hasAccess(paths: UserPaths.current())
    }
}

/// 앱 밖으로 나가는 링크들. 한 곳에 모아둔다.
enum SupportLinks {
    static let repository = URL(string: "https://github.com/agshwanbong-max/my-mac")!
    /// 후원 페이지 (GitHub Sponsors).
    /// 앱에도 이 페이지에도 광고는 없다 — 전체 디스크 접근을 요구하는 앱에서
    /// 광고는 권한을 내주게 만드는 신뢰를 가장 비싸게 깎는다.
    static let support = URL(string: "https://agshwanbong-max.github.io/my-mac/support.html")!
    static let releases = URL(string: "https://github.com/agshwanbong-max/my-mac/releases")!
}
#endif
