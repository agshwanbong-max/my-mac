#if os(macOS)
import MacCleanCore
import SwiftUI

/// 새 버전이 나왔다는 알림.
///
/// 시트가 아니라 배너인 이유: 사용자가 하려던 일을 끊지 않기 위해서다.
/// 업데이트는 급한 일이 아니다. 보이되 막지 않는다.
struct UpdateBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let manifest = model.availableUpdate {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text("새 버전 \(manifest.version) 이 나왔습니다")
                        .font(.callout.weight(.medium))
                    Text("지금 쓰시는 건 \(model.currentVersion) 입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("나중에") { model.dismissUpdate() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("받으러 가기") { model.openDownloadPage() }
                    .controlSize(.small)
            }
            .padding(.horizontal, Design.gutter)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.10))
        }
    }
}
#endif
