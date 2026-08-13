#if os(macOS)
import MacCleanCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            DetailView()
        }
        .navigationTitle("MacClean")
        .toolbar { toolbarContent }
        .onAppear {
            if model.report == nil { model.startScan() }
        }
        .sheet(isPresented: $model.isConfirming) { ConfirmSheet() }
        .sheet(isPresented: $model.isShowingResults) { ResultsSheet() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if model.phase == .scanning {
                Button {
                    model.cancelScan()
                } label: {
                    Label("검사 중단", systemImage: "stop.circle")
                }
                .help("검사를 중단합니다")
            } else {
                Button {
                    model.startScan()
                } label: {
                    Label("다시 검사", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("다시 검사합니다")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.includeLargeFiles) {
                Label("대용량 파일 포함", systemImage: "doc.richtext")
            }
            .toggleStyle(.button)
            .help("홈 전체를 훑어 대용량 파일까지 찾습니다. 검사가 느려집니다.")
            .disabled(model.isBusy)
        }
    }
}
#endif
