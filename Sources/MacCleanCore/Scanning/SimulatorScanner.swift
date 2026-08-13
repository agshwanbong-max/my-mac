import Foundation

/// iOS 시뮬레이터 관련 후보를 찾는다.
///
/// 시뮬레이터 기기 데이터는 파일을 직접 지우면 CoreSimulator 의 인덱스와 어긋난다.
/// 그래서 여기서는 **파일을 건드리지 않고** `xcrun simctl delete` 로만 처리한다.
/// (그 명령은 `ToolCommand.allowedPrefixes` 에 등록돼 있다.)
public struct SimulatorScanner: Scanner {

    public let identifier = "simulators"

    private let runner: ShellRunner
    private let usage = DiskUsage()

    public init(runner: ShellRunner = ShellRunner()) {
        self.runner = runner
    }

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        var findings: [Finding] = []
        var warnings: [ScanWarning] = []

        let devicesRoot = context.paths.resolve("Library/Developer/CoreSimulator/Devices")
        guard FileManager.default.fileExists(atPath: devicesRoot.path) else {
            return ([], [])
        }

        if context.isRunning("com.apple.iphonesimulator") || context.isRunning("com.apple.CoreSimulator.SimulatorTrampoline") {
            warnings.append(ScanWarning(
                ruleID: "simulator.devices",
                message: "시뮬레이터가 실행 중이라 시뮬레이터 항목을 건너뛰었습니다. 종료 후 다시 검사하세요."
            ))
            return ([], warnings)
        }

        let unavailable = unavailableDeviceIdentifiers()
        if unavailable.isEmpty {
            // 목록을 못 읽었거나 정말 없는 경우. 전자면 경고를 남긴다.
            if !simctlAvailable() {
                warnings.append(ScanWarning(
                    ruleID: "simulator.devices",
                    message: "xcrun 을 실행할 수 없어 시뮬레이터 검사를 건너뛰었습니다."
                ))
            }
            return (findings, warnings)
        }

        // 기기마다 후보를 하나씩 만들면 목록이 10줄씩 늘어난다 (실제로 그랬다).
        // `simctl delete unavailable` 한 번이면 전부 정리되므로 후보도 하나로 묶는다.
        var totalBytes: Int64 = 0
        var totalFiles = 0
        var newest: Date?
        var counted = 0

        for udid in unavailable {
            if isCancelled() { break }
            let deviceDirectory = devicesRoot.appendingPathComponent(udid)
            guard FileManager.default.fileExists(atPath: deviceDirectory.path) else { continue }

            let measurement = usage.measure(deviceDirectory, isCancelled: isCancelled)
            totalBytes += measurement.allocatedBytes
            totalFiles += measurement.fileCount
            counted += 1
            if let modified = measurement.newestModification, newest == nil || modified > newest! {
                newest = modified
            }
        }

        if counted > 0 {
            findings.append(Finding(
                id: "simulator.unavailable",
                ruleID: "simulator.unavailable",
                category: .simulators,
                risk: .safe,
                title: "사용할 수 없는 시뮬레이터 기기 \(counted)대",
                detail: "쓰던 런타임이 더 이상 설치돼 있지 않아 Xcode 에서 실행할 수 없는 기기들입니다.",
                consequence: "`xcrun simctl delete unavailable` 로 한 번에 정상 삭제됩니다. "
                    + "필요하면 Xcode 에서 같은 기기를 새로 만들 수 있습니다.",
                path: devicesRoot,
                reclaimableBytes: totalBytes,
                itemCount: totalFiles,
                lastModified: newest,
                removal: .toolCommand,
                toolCommand: ToolCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"])
            ))
        }

        // 런타임(각 7~10GB)은 안내만 한다. Xcode 설정에서 지우는 게 정석이다.
        let runtimes = context.paths.resolve("Library/Developer/CoreSimulator/Profiles/Runtimes")
        if let children = try? FileManager.default.contentsOfDirectory(
            at: runtimes, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ), !children.isEmpty {
            let measurement = usage.measure(runtimes, isCancelled: isCancelled)
            if measurement.allocatedBytes > 5_000_000_000 {
                findings.append(Finding(
                    id: "simulator.runtimes",
                    ruleID: "simulator.runtimes",
                    category: .simulators,
                    risk: .advisory,
                    title: "설치된 시뮬레이터 런타임 \(children.count)개 · \(ByteFormat.string(measurement.allocatedBytes))",
                    detail: "iOS 버전마다 런타임이 한 벌씩 설치됩니다. 하나에 7~10GB 씩 합니다.",
                    consequence: "Xcode → Settings → Platforms 에서 안 쓰는 버전을 지우세요. "
                        + "파일을 직접 지우면 Xcode 의 목록과 어긋나므로 이 앱은 건드리지 않습니다.",
                    path: runtimes,
                    reclaimableBytes: 0,
                    itemCount: children.count,
                    lastModified: measurement.newestModification,
                    removal: .adviseOnly
                ))
            }
        }

        return (findings, warnings)
    }

    private func simctlAvailable() -> Bool {
        (try? runner.run(executable: "/usr/bin/xcrun", arguments: ["simctl", "help"], timeout: 10))?.succeeded ?? false
    }

    /// `xcrun simctl list devices -j` 를 읽어 `isAvailable == false` 인 기기의 UDID 를 뽑는다.
    private func unavailableDeviceIdentifiers() -> [String] {
        guard let result = try? runner.run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j"],
            timeout: 30
        ), result.succeeded, let data = result.standardOutput.data(using: .utf8) else {
            return []
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = root["devices"] as? [String: Any]
        else {
            return []
        }

        var identifiers: [String] = []
        for (_, value) in devices {
            guard let list = value as? [[String: Any]] else { continue }
            for device in list {
                let available = device["isAvailable"] as? Bool ?? true
                guard !available, let udid = device["udid"] as? String else { continue }
                identifiers.append(udid)
            }
        }
        return identifiers
    }
}
