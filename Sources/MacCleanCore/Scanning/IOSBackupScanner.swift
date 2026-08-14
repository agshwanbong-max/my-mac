import Foundation

/// iPhone / iPad 로컬 백업을 찾는다.
///
/// 보통 한 대에 10~50GB 다. 256GB 맥에서 "시스템 데이터"를 크게 부풀리는 주범 중 하나.
/// 하지만 **이게 유일한 백업일 수 있으므로** 항상 `.review` 이고, 항상 휴지통으로만 보낸다.
/// 기기 이름과 마지막 백업 날짜를 읽어서 사용자가 판단할 수 있게 해준다.
public struct IOSBackupScanner: Scanner {

    public let identifier = "iosBackup"

    private let usage = DiskUsage()

    public init() {}

    public func scan(context: ScanContext, isCancelled: () -> Bool) -> (findings: [Finding], warnings: [ScanWarning]) {
        let root = context.paths.resolve("Library/Application Support/MobileSync/Backup")
        guard FileManager.default.fileExists(atPath: root.path) else { return ([], []) }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return ([], [ScanWarning(
                ruleID: "ios.backups",
                message: L("warn.iosBackupUnreadable")
            )])
        }

        // 이 폴더는 `ProtectedPaths` 의 기본 보호 목록에 들어 있다.
        // 백업만큼은 사용자가 명시적으로 고를 수 있어야 하므로, **이 접두사 하나만** 예외로 연다.
        // 나머지 게이트(링크·소유권·볼륨·깊이·쓰기권한)는 그대로 전부 적용된다.
        // 깊이를 root+1 로 못박아서, 백업 폴더 자체나 그 안쪽 깊은 파일은 대상이 될 수 없다.
        let rootDepth = root.standardizedFileURL.pathComponents.count - 1
        let constraints = RuleConstraints(
            allowedRoots: [root],
            minimumDepth: rootDepth + 1,
            exemptProtectedPrefix: root
        )
        let guardian = PathGuard(paths: context.paths)

        var findings: [Finding] = []
        for child in children {
            if isCancelled() { break }

            // 백업 루트 바로 아래 한 단계(기기 UDID 폴더)만 대상이다.
            guard child.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else {
                continue
            }
            guard guardian.evaluate(child, constraints: constraints).allowed else { continue }

            let measurement = usage.measure(child, isCancelled: isCancelled)
            guard measurement.allocatedBytes >= 100_000_000 else { continue }

            let info = readBackupInfo(child)
            let deviceName = info.deviceName ?? child.lastPathComponent
            let backupDate = info.lastBackupDate

            var detail = L("iosBackup.device", deviceName)
            if let productName = info.productName { detail += " (\(productName))" }
            if let date = backupDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                detail += L("iosBackup.lastBackup", formatter.string(from: date))
            }

            findings.append(Finding(
                id: "ios.backup|\(child.path)",
                ruleID: "ios.backups",
                category: .iosBackup,
                risk: .review,
                title: L("iosBackup.title", deviceName),
                detail: detail,
                consequence: """
                ⚠️ 이게 이 기기의 유일한 백업이라면 복원할 방법이 사라집니다.
                iCloud 백업을 켜뒀거나 최근 백업이 따로 있을 때만 지우세요.
                휴지통으로 이동하므로 휴지통을 비우기 전까지는 되돌릴 수 있습니다.
                """,
                path: child,
                reclaimableBytes: measurement.allocatedBytes,
                itemCount: measurement.fileCount,
                lastModified: backupDate ?? measurement.newestModification,
                removal: .trashItem,
                constraints: constraints
            ))
        }

        return (findings, [])
    }

    private struct BackupInfo {
        var deviceName: String?
        var productName: String?
        var lastBackupDate: Date?
    }

    private func readBackupInfo(_ directory: URL) -> BackupInfo {
        let plistURL = directory.appendingPathComponent("Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return BackupInfo(deviceName: nil, productName: nil, lastBackupDate: nil)
        }

        return BackupInfo(
            deviceName: plist["Device Name"] as? String,
            productName: plist["Product Name"] as? String,
            lastBackupDate: plist["Last Backup Date"] as? Date
        )
    }
}
