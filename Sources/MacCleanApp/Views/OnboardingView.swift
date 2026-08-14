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
                        title: "용량이 어디에 있는지 알려줍니다",
                        body: "macOS 의 '시스템 데이터'가 무엇으로 채워져 있는지 폴더 단위로 보여줍니다. "
                            + "그다음 그중 지워도 되는 것을 골라줍니다."
                    )

                    permissionSection

                    section(
                        icon: "hand.raised.fill",
                        tint: .green,
                        title: "이런 것은 하지 않습니다",
                        body: """
                        · 문서·사진·iCloud·자격 증명은 코드에서 막혀 있습니다. 규칙으로도 뚫을 수 없습니다.
                        · 기본 처리는 휴지통 이동입니다. 되돌릴 수 있습니다.
                        · 관리자 권한을 요구하지 않습니다.
                        · 무엇을 왜 지우는지 항목마다 설명하고, 실행 전에 한 번 더 확인합니다.
                        """
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
                Text("저장 공간을 정리합니다. 잘못 지우는 일 없이.")
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
                title: hasAccess ? "전체 디스크 접근이 켜져 있습니다" : "전체 디스크 접근이 필요합니다",
                body: hasAccess
                    ? "iPhone 백업, 메일 첨부 임시본, 샌드박스 앱 캐시까지 전부 검사할 수 있습니다."
                    : """
                    macOS 는 이 권한 없이는 ~/Library 의 상당 부분을 아예 안 보이게 가립니다. \
                    빈 폴더처럼 보일 뿐 오류도 나지 않아서, 권한이 없으면 앱이 조용히 절반만 찾습니다.

                    이 권한으로 읽기만 합니다. 무엇을 지울지는 화면에서 직접 고르십니다.
                    """
            )

            if !hasAccess {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        model.openFullDiskAccessSettings()
                    } label: {
                        Label("전체 디스크 접근 설정 열기", systemImage: "arrow.up.forward.app")
                    }
                    .primaryAction()

                    Text("설정이 열리면 목록에서 MacClean 을 켜고 이 창으로 돌아오세요. 자동으로 다시 확인합니다.")
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
            Link("소스 코드", destination: SupportLinks.repository)
                .font(.caption)
            Link("후원하기", destination: SupportLinks.support)
                .font(.caption)

            Spacer()

            // 권한 없이도 시작할 수 있어야 한다. 강제하면 앱을 닫아버린다.
            // 대신 그 상태로는 절반만 찾는다는 걸 알고 시작하게 만든다.
            Button(hasAccess ? "시작하기" : "권한 없이 시작") {
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
