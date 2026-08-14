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
            VStack(spacing: 0) {
                // 새 버전 알림은 목록 위에 얹는다. 시트로 띄우면 하던 일을 끊는다.
                if model.availableUpdate != nil {
                    UpdateBanner()
                    Divider()
                }
                DetailView()
            }
        }
        .navigationTitle("MacClean")
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
        .alert("업데이트", isPresented: .constant(model.updateMessage != nil)) {
            Button("확인") { model.updateMessage = nil }
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
            Toggle(isOn: $model.includeDeepScan) {
                Label("정밀 분석", systemImage: "chart.pie")
            }
            .toggleStyle(.button)
            .help("홈 전체를 훑어 용량이 어디에 있는지와 대용량 파일을 찾습니다. 수십 초 걸립니다.")
            .disabled(model.isBusy)
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.includeDuplicates) {
                Label("중복 찾기", systemImage: "doc.on.doc")
            }
            .toggleStyle(.button)
            .help("문서·다운로드·사진 폴더에서 내용이 완전히 같은 파일을 찾습니다. 파일을 해시하므로 가장 오래 걸립니다.")
            .disabled(model.isBusy)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.isShowingRestore = true
            } label: {
                Label("되돌리기", systemImage: "arrow.uturn.backward")
            }
            .help("이 앱이 휴지통으로 옮긴 것을 원래 자리로 되돌립니다")
        }
    }
}
#endif
