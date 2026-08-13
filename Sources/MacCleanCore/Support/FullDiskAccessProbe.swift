import Foundation

/// 전체 디스크 접근(Full Disk Access) 권한이 있는지 확인한다.
///
/// macOS 는 이 권한 없이는 `~/Library/Application Support/MobileSync`,
/// `~/Library/Containers/com.apple.mail` 같은 곳을 읽지 못한다.
/// 권한이 없으면 조용히 "빈 폴더"처럼 보이기 때문에, 스캔 결과가 이유 없이 작아진다.
/// 그 상황을 사용자에게 알려주기 위해 미리 찔러본다.
public enum FullDiskAccessProbe {

    /// 권한이 있어야만 읽히는 경로들. 하나라도 읽히면 권한이 있는 것으로 본다.
    private static let probePaths = [
        "Library/Application Support/MobileSync",
        "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
        "Library/Safari",
    ]

    public static func hasAccess(paths: UserPaths) -> Bool {
        let fileManager = FileManager.default

        for relative in probePaths {
            let url = paths.resolve(relative)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            if (try? fileManager.contentsOfDirectory(atPath: url.path)) != nil {
                return true
            }
        }

        // 찔러볼 경로가 하나도 존재하지 않는 깨끗한 시스템이라면 판단할 수 없다.
        // 이럴 땐 "있다"고 보고 진행한다 — 없는 걸 있다고 잘못 경고하는 것보다 낫다.
        let anyExists = probePaths.contains { fileManager.fileExists(atPath: paths.resolve($0).path) }
        return !anyExists
    }

    public static let instructions = """
    시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 에서 MacClean 을 켜주세요.
    이 권한이 없으면 iPhone 백업, 메일 첨부 임시본, 샌드박스 앱 캐시를 찾지 못합니다.
    """
}
