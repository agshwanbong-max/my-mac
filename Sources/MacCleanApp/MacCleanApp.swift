#if os(macOS)
import SwiftUI

struct MacCleanApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MacClean") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("다시 검사") { model.startScan() }
                    .keyboardShortcut("r")
            }
        }
    }
}
#endif
