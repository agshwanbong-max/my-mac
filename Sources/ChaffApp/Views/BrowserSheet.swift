#if os(macOS)
import AppKit
import ChaffCore
import SwiftUI

/// 규칙이 없는 폴더를 직접 열어 고르는 화면.
///
/// 이 앱의 다른 모든 화면과 성격이 다르다. 나머지는 미리 검증한 목록만 다루는데
/// 여기서는 사용자가 임의의 폴더를 열고 스스로 고른다.
/// 그래서 **경고를 접을 수 없게** 화면 맨 위에 고정으로 붙여둔다.
struct BrowserSheet: View {
    @EnvironmentObject private var model: AppModel
    let directory: URL

    @State private var entries: [DirectoryBrowser.Entry] = []
    @State private var selection: Set<String> = []
    @State private var isLoading = true

    private var paths: UserPaths { UserPaths.current() }

    private var selectedEntries: [DirectoryBrowser.Entry] {
        entries.filter { selection.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedEntries.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            warning
            Divider()

            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L("browser.measuring"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                Text(L("browser.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        .task { await load() }
    }

    // MARK: -

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(directory.lastPathComponent)
                    .font(.headline)
                Text(paths.abbreviate(directory))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(L("browser.openInFinder")) {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
            .controlSize(.small)
        }
        .padding(16)
    }

    /// 접을 수 없다. 이 화면에서 무슨 일이 벌어지는지 사용자가 놓치면 안 된다.
    private var warning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("browser.warning"))
                    .font(.callout.weight(.semibold))
                Text("""
                    앱이 아는 안전한 경로가 아니라, 폴더를 그대로 열어 보여주는 화면입니다. \
                    무엇을 지울지는 직접 판단하셔야 합니다. 앱이 붙여주는 판정은 참고용입니다.
                    선택한 항목은 **휴지통으로만** 갑니다. 이상하면 휴지통에서 되돌리세요.
                    문서·사진·iCloud·자격 증명은 여기서도 지울 수 없게 막혀 있습니다.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    row(entry)
                    Divider().padding(.leading, 46)
                }
            }
        }
    }

    private func row(_ entry: DirectoryBrowser.Entry) -> some View {
        let isSelected = selection.contains(entry.id)

        return HStack(spacing: 12) {
            if entry.isRemovable {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .help(entry.blockedReason ?? L("browser.blocked"))
            }

            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .lineLimit(1)
                    VerdictBadge(verdict: entry.assessment.verdict)
                }
                Text(entry.isRemovable ? entry.assessment.headline : (entry.blockedReason ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(ByteFormat.stringOrDash(entry.bytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(entry.isRemovable ? .primary : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            guard entry.isRemovable else { return }
            if isSelected { selection.remove(entry.id) } else { selection.insert(entry.id) }
        }
        .contextMenu {
            Button(L("row.menu.revealInFinder")) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Button(L("row.menu.copyPath")) { model.copyToPasteboard(entry.url.path) }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(L("action.selectionSummary", selectedEntries.count, ByteFormat.string(selectedBytes)))
                .font(.callout.weight(.medium))
                .contentTransition(.numericText())

            if selectedEntries.contains(where: { $0.assessment.verdict == .keep }) {
                Label(L("browser.containsKeep"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button(L("common.close")) { model.browsingDirectory = nil }
                .secondaryAction()

            Button(L("browser.addToList")) {
                let browser = DirectoryBrowser(paths: paths)
                model.addManualSelections(selectedEntries.map { browser.finding(for: $0) })
                model.browsingDirectory = nil
            }
            .primaryAction()
            .disabled(selectedEntries.isEmpty)
        }
        .padding(16)
    }

    // MARK: -

    private func load() async {
        let target = directory
        let userPaths = paths

        let loaded = await Task.detached(priority: .userInitiated) {
            DirectoryBrowser(paths: userPaths).open(target)
        }.value

        entries = loaded
        isLoading = false
    }
}
#endif
