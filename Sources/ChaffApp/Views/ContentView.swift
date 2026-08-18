#if os(macOS)
import ChaffCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                // 새 버전 알림은 목록 위에 얹는다. 시트로 띄우면 하던 일을 끊는다.
                if model.availableUpdate != nil {
                    UpdateBanner()
                    Divider()
                }
                DetailView()
            }
        }
        .navigationTitle("Chaff")
        .toolbar { toolbarContent }
        .onAppear {
            // 첫 실행이면 안내를 먼저 본다. 검사는 안내를 닫은 뒤에 시작한다.
            if model.report == nil && !model.isShowingOnboarding { model.startScan() }
            model.checkForUpdatesIfDue()
        }
        .sheet(isPresented: $model.isConfirming) { ConfirmSheet() }
        .sheet(isPresented: $model.isShowingResults) { ResultsSheet() }
        .sheet(isPresented: $model.isShowingOnboarding) {
            OnboardingView().environmentObject(model)
        }
        .sheet(isPresented: $model.isShowingRestore) {
            RestoreSheet().environmentObject(model)
        }
        .sheet(item: $model.browsingDirectory) { directory in
            BrowserSheet(directory: directory.url)
                .environmentObject(model)
        }
        .alert(L("update.alertTitle"), isPresented: .constant(model.updateMessage != nil)) {
            Button(L("common.ok")) { model.updateMessage = nil }
        } message: {
            Text(model.updateMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if model.phase == .scanning {
                Button {
                    model.cancelScan()
                } label: {
                    Label(L("toolbar.stopScan"), systemImage: "stop.circle")
                }
                .help(L("toolbar.stopScan.help"))
            } else {
                Button {
                    model.startScan()
                } label: {
                    Label(L("action.rescan"), systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help(L("action.rescan.help"))
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.includeDeepScan) {
                Label(L("toolbar.deepScan"), systemImage: "chart.pie")
            }
            .toggleStyle(.button)
            .help(L("toolbar.deepScan.help"))
            .disabled(model.isBusy)
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.includeDuplicates) {
                Label(L("toolbar.duplicates"), systemImage: "doc.on.doc")
            }
            .toggleStyle(.button)
            .help(L("toolbar.duplicates.help"))
            .disabled(model.isBusy)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.isShowingRestore = true
            } label: {
                Label(L("toolbar.restore"), systemImage: "arrow.uturn.backward")
            }
            .help(L("toolbar.restore.help"))
        }
    }
}
#endif
