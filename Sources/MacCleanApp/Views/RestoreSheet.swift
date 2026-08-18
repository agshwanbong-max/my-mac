#if os(macOS)
import AppKit
import MacCleanCore
import SwiftUI

/// 이 앱이 휴지통으로 옮긴 것을 원래 자리로 되돌린다.
///
/// 이 앱은 처음부터 "되돌릴 수 있게" 를 원칙으로 삼았는데, 정작 되돌리는 건
/// 사용자가 파인더에서 손으로 해야 했다. 항목이 수십 개면 어느 게 이 앱이 옮긴 것인지도 모른다.
/// 감사 로그에 원래 경로와 휴지통 안의 위치가 다 남아 있으니, 읽어서 되돌리기만 하면 된다.
struct RestoreSheet: View {
    @EnvironmentObject private var model: AppModel

    @State private var entries: [RestoreService.Entry] = []
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                    Text(L("restore.empty.title"))
                        .font(.headline)
                    Text(L("restore.empty.detail"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(width: 720, height: 520)
        .onAppear { entries = model.restorableEntries() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("restore.title"))
                .font(.headline)
            Text(L("restore.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    row(entry)
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    private func row(_ entry: RestoreService.Entry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.originalPath.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                Text(UserPaths.current().abbreviate(entry.originalPath.deletingLastPathComponent()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let reason = entry.blockedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.stringOrDash(entry.bytes))
                    .font(.callout.monospacedDigit())
                Text(entry.removedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(L("restore.action")) {
                switch model.restore(entry) {
                case .restored(let url):
                    message = L("restore.moved", url.lastPathComponent)
                case .failed(let reason):
                    message = reason
                }
                entries = model.restorableEntries()
            }
            .controlSize(.small)
            .disabled(!entry.isRestorable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contextMenu {
            Button(L("restore.showInTrash")) {
                NSWorkspace.shared.activateFileViewerSelecting([entry.trashedTo])
            }
        }
    }

    private var footer: some View {
        HStack {
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(L("common.close")) { model.isShowingRestore = false }
                .primaryAction()
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
#endif
