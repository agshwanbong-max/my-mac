import Foundation

/// "시스템 데이터"가 왜 부풀어 있는지 진단한다.
///
/// 이 스캐너는 **아무것도 지우지 않는다.** 전부 `.advisory` 다.
/// 그런데도 이 앱에서 가장 중요한 부분인 이유:
///
/// Time Machine 로컬 스냅샷이 남아 있으면, 파일을 아무리 지워도 **여유 공간이 늘지 않는다.**
/// 지운 파일의 블록을 스냅샷이 계속 붙잡고 있기 때문이다.
/// 그래서 "정리했는데 용량이 그대로"라는 현상이 생기고, 그 용량이 "시스템 데이터"로 집계된다.
///
/// 스냅샷 삭제는 `sudo` 가 필요하다. 이 앱은 관리자 권한을 절대 요구하지 않으므로,
/// 진단 결과와 사용자가 직접 실행할 명령만 보여준다.
public struct SystemDataScanner: Scanner {

    public let identifier = "systemData"

    private let probe: VolumeProbe

    public init(probe: VolumeProbe = VolumeProbe()) {
        self.probe = probe
    }

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        var findings: [Finding] = []
        let snapshot = probe.snapshot(home: context.paths.home)
        let classified = probe.classifiedSnapshots()
        let snapshotNames = classified.timeMachine + classified.osUpdate

        if !classified.timeMachine.isEmpty {
            findings.append(snapshotFinding(names: classified.timeMachine, volume: snapshot))
        }
        if !classified.osUpdate.isEmpty {
            findings.append(osUpdateSnapshotFinding(names: classified.osUpdate))
        }

        if snapshot.purgeableEstimate > 5_000_000_000 {
            findings.append(purgeableFinding(volume: snapshot))
        }

        findings.append(explainerFinding(volume: snapshot, snapshotCount: snapshotNames.count))

        return (findings, [])
    }

    private func snapshotFinding(names: [String], volume: VolumeSnapshot) -> Finding {
        let dates = names.compactMap { name -> String? in
            // com.apple.TimeMachine.2026-08-10-141530.local → 2026-08-10 14:15
            guard let range = name.range(of: "com.apple.TimeMachine.") else { return nil }
            let rest = String(name[range.upperBound...])
            return rest.replacingOccurrences(of: ".local", with: "")
        }

        let oldest = dates.min() ?? "-"
        let newest = dates.max() ?? "-"

        return Finding(
            id: "systemData.localSnapshots",
            ruleID: "systemData.localSnapshots",
            category: .systemDataDiagnosis,
            risk: .advisory,
            title: L("systemData.tmSnapshots.title", names.count),
            detail: """
            \(oldest) ~ \(newest) 사이에 만들어진 스냅샷이 내장 디스크에 남아 있습니다.
            이 스냅샷들은 그동안 지운 파일의 데이터를 그대로 붙잡고 있습니다.
            그래서 파일을 지워도 여유 공간이 늘지 않고, 그 용량이 '시스템 데이터'로 집계됩니다.
            256GB 맥에서 '시스템 데이터'가 비정상적으로 커 보이는 원인 1순위입니다.
            """,
            consequence: """
            보통은 그냥 둬도 됩니다 — macOS 가 공간이 부족해지면 알아서 지웁니다.
            지금 당장 공간이 필요하면 아래 명령으로 직접 비울 수 있습니다.
            지우면 그 시점으로 되돌리는 로컬 복구는 불가능해집니다 (외장 Time Machine 백업은 그대로입니다).
            이 앱은 관리자 권한을 쓰지 않으므로 직접 실행하지 않습니다.
            """,
            path: nil,
            reclaimableBytes: 0,
            itemCount: names.count,
            lastModified: nil,
            removal: .adviseOnly,
            suggestedCommand: "tmutil listlocalsnapshots /\nsudo tmutil thinlocalsnapshots / 21474836480 4"
        )
    }

    /// macOS 업데이트 스냅샷.
    ///
    /// Time Machine 을 한 번도 안 켠 맥에도 이건 생긴다.
    /// `MSUPrepareUpdate` 는 받아서 준비하다 만 업데이트라, 설치도 안 되고 공간만 잡고 있는 상태다.
    private func osUpdateSnapshotFinding(names: [String]) -> Finding {
        let hasStalledUpdate = names.contains { $0.contains("MSUPrepareUpdate") }

        var detail = """
        macOS 업데이트 과정에서 만들어진 스냅샷 \(names.count)개가 남아 있습니다.
        Time Machine 을 쓰지 않아도 생기며, 지운 파일의 블록을 붙잡고 있어서
        정리를 해도 여유 공간이 늘지 않게 만듭니다. '시스템 데이터'로 집계되는 부분입니다.
        """
        if hasStalledUpdate {
            detail += """


            ⚠️ 준비하다 만 업데이트(MSUPrepareUpdate)가 있습니다.
            받아놓고 설치하지 않은 상태라 몇 GB 를 그냥 잡고 있을 수 있습니다.
            시스템 설정 → 일반 → 소프트웨어 업데이트 에서 설치를 끝내는 게 가장 확실한 정리입니다.
            """
        }

        return Finding(
            id: "systemData.osUpdateSnapshots",
            ruleID: "systemData.osUpdateSnapshots",
            category: .systemDataDiagnosis,
            risk: .advisory,
            title: L("systemData.updateSnapshots.title", names.count),
            detail: detail,
            consequence: """
            업데이트를 끝내면 대부분 저절로 정리됩니다.
            그래도 남아 있고 공간이 급하면 아래 명령으로 직접 지울 수 있습니다.
            이 앱은 관리자 권한을 쓰지 않으므로 직접 실행하지 않습니다.
            """,
            path: nil,
            reclaimableBytes: 0,
            itemCount: names.count,
            lastModified: nil,
            removal: .adviseOnly,
            suggestedCommand: "tmutil listlocalsnapshots /\nsudo tmutil deletelocalsnapshots <snapshot-name>"
        )
    }

    private func purgeableFinding(volume: VolumeSnapshot) -> Finding {
        Finding(
            id: "systemData.purgeable",
            ruleID: "systemData.purgeable",
            category: .systemDataDiagnosis,
            risk: .advisory,
            title: L("systemData.purgeable.title", ByteFormat.string(volume.purgeableEstimate)),
            detail: """
            macOS 가 '사용 가능'이라고 표시하는 용량과 실제 빈 공간의 차이입니다.
            스냅샷, 캐시, iCloud 로 올려둔 파일의 로컬 사본 등이 여기 들어갑니다.
            시스템은 공간이 정말 필요할 때 이걸 알아서 회수합니다.
            """,
            consequence: L("systemData.purgeable.consequence"),
            path: nil,
            reclaimableBytes: 0,
            itemCount: 0,
            lastModified: nil,
            removal: .adviseOnly
        )
    }

    private func explainerFinding(volume: VolumeSnapshot, snapshotCount: Int) -> Finding {
        let used = volume.totalCapacity - volume.availableCapacity
        return Finding(
            id: "systemData.explainer",
            ruleID: "systemData.explainer",
            category: .systemDataDiagnosis,
            risk: .advisory,
            title: L("systemData.volume.title"),
            detail: """
            전체 \(ByteFormat.string(volume.totalCapacity)) 중 \(ByteFormat.string(used)) 사용 중.
            실제 빈 공간 \(ByteFormat.string(volume.availableCapacity)),
            시스템이 회수 가능한 공간까지 포함하면 \(ByteFormat.string(volume.availableForImportantUsage)).
            로컬 스냅샷 \(snapshotCount)개.
            """,
            consequence: L("systemData.volume.consequence"),
            path: nil,
            reclaimableBytes: 0,
            itemCount: 0,
            lastModified: nil,
            removal: .adviseOnly
        )
    }
}
