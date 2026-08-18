#if os(macOS)
import AppKit
import ChaffCore
import SwiftUI

struct ChaffApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Chaff") {
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
                Button(L("action.rescan")) { model.startScan() }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .appInfo) {
                Button(L("menu.checkUpdates")) { model.checkForUpdates(announceNoUpdate: true) }
                Divider()
                Button(L("menu.support.item")) { NSWorkspace.shared.open(SupportLinks.support) }
                Button(L("menu.sourceCode")) { NSWorkspace.shared.open(SupportLinks.repository) }
            }
        }
    }
}
#endif
