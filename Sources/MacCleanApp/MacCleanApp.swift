#if os(macOS)
import AppKit
import SwiftUI

struct MacCleanApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MacClean") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        // 도구 막대를 제목 줄과 한 덩어리로. macOS 26 의 유리 도구 막대도 이 스타일에서 가장 잘 붙는다.
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("다시 검사") { model.startScan() }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") { model.checkForUpdates(announceNoUpdate: true) }
                Divider()
                Button("후원하기…") { NSWorkspace.shared.open(SupportLinks.support) }
                Button("소스 코드 보기") { NSWorkspace.shared.open(SupportLinks.repository) }
            }
        }
    }
}
#endif
