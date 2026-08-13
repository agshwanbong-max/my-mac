#if os(macOS)
import MacCleanCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            DiskHeader()
            Divider()

            if !model.hasFullDiskAccess {
                PermissionBanner()
                Divider()
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            ActionBar()
        }
        .onAppear {
            if model.report == nil { model.startScan() }
        }
        .sheet(isPresented: $model.isConfirming) { ConfirmSheet() }
        .sheet(isPresented: $model.isShowingResults) { ResultsSheet() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .scanning:
            ScanningView()
        case .ready, .finished, .executing:
            if let report = model.report {
                FindingList(report: report)
            } else {
                ScanningView()
            }
        }
    }
}

// MARK: - 디스크 현황

private struct DiskHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let volume = model.report?.volume ?? VolumeSnapshot.unknown
        let used = max(0, volume.totalCapacity - volume.availableCapacity)
        let usedRatio = volume.totalCapacity > 0 ? Double(used) / Double(volume.totalCapacity) : 0

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("저장 공간")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.startScan()
                } label: {
                    Label("다시 검사", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.18))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(usedRatio > 0.9 ? Color.red : (usedRatio > 0.75 ? Color.orange : Color.accentColor))
                        .frame(width: geometry.size.width * usedRatio)
                }
            }
            .frame(height: 10)

            HStack(spacing: 16) {
                Text("사용 중 \(ByteFormat.string(used))")
                Text("여유 \(ByteFormat.string(volume.availableCapacity))")
                if volume.purgeableEstimate > 0 {
                    Text("회수 가능 \(ByteFormat.string(volume.purgeableEstimate))")
                        .foregroundStyle(.secondary)
                }
                if volume.localSnapshotCount > 0 {
                    Label("로컬 스냅샷 \(volume.localSnapshotCount)개", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .font(.callout)
        }
        .padding(20)
    }
}

private struct PermissionBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("전체 디스크 접근 권한이 없습니다")
                    .font(.callout.weight(.semibold))
                Text(FullDiskAccessProbe.instructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("설정 열기") { model.openFullDiskAccessSettings() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.10))
    }
}

private struct ScanningView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(model.phase == .scanning ? "검사 중입니다…" : "검사를 시작합니다")
                .font(.callout)
            Text("이 단계에서는 아무것도 지우지 않습니다. 읽기만 합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 결과 목록

private struct FindingList: View {
    @EnvironmentObject private var model: AppModel
    let report: ScanReport

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(report.categoriesInOrder, id: \.self) { category in
                    Section {
                        if !model.collapsedCategories.contains(category) {
                            ForEach(report.findings(in: category)) { finding in
                                FindingRow(finding: finding)
                                Divider().padding(.leading, 44)
                            }
                        }
                    } header: {
                        CategoryHeader(category: category, findings: report.findings(in: category))
                    }
                }

                if !report.warnings.isEmpty {
                    WarningsBlock(warnings: report.warnings)
                }
            }
        }
    }
}

private struct CategoryHeader: View {
    @EnvironmentObject private var model: AppModel
    let category: FindingCategory
    let findings: [Finding]

    private var selectable: [Finding] { findings.filter { $0.isSelectable } }
    private var subtotal: Int64 { selectable.reduce(0) { $0 + $1.reclaimableBytes } }
    private var allSelected: Bool {
        !selectable.isEmpty && selectable.allSatisfy { model.selection.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleCollapse(category)
            } label: {
                Image(systemName: model.collapsedCategories.contains(category) ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Text(category.localizedTitle)
                .font(.headline)

            Text("\(findings.count)건")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if subtotal > 0 {
                Text(ByteFormat.string(subtotal))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !selectable.isEmpty {
                Button(allSelected ? "전체 해제" : "전체 선택") {
                    model.setSelection(for: category, selected: !allSelected)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct WarningsBlock: View {
    let warnings: [ScanWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("검사 중 건너뛴 항목")
                .font(.headline)
            ForEach(warnings) { warning in
                Text("· \(warning.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

// MARK: - 액션 바

private struct ActionBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            if case .executing(let current, let total) = model.phase {
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                    .frame(width: 160)
                Text("\(current) / \(total)")
                    .font(.callout.monospacedDigit())
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("선택 \(model.selectedFindings.count)건 · \(ByteFormat.string(model.selectedBytes))")
                        .font(.callout.weight(.medium))
                    Text("선택한 항목은 기본적으로 휴지통으로 이동합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("미리보기") {
                model.performCleanup(dryRun: true)
            }
            .disabled(model.selectedFindings.isEmpty || model.isBusy)

            Button("정리 실행") {
                model.requestCleanup()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selectedFindings.isEmpty || model.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
#endif
