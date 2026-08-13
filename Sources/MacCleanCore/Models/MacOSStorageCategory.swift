import Foundation

/// macOS 저장 공간 화면의 칸.
///
/// 이 매핑이 필요한 이유:
/// 사용자가 보는 숫자는 시스템 설정의 "시스템 데이터 71GB" 다.
/// 앱이 "~/Library/Application Support/Claude 13GB" 라고 말해도,
/// 그게 그 71GB 안에 들어가는 건지 아닌지 알 수 없으면 아무 도움이 안 된다.
///
/// 실제로 이 혼란이 있었다. iOS DeviceSupport 17GB 를 지우면 시스템 데이터가 줄 것 같지만,
/// 그건 '개발자' 칸에 들어 있어서 시스템 데이터는 그대로다.
public enum MacOSStorageCategory: String, Codable, Sendable, CaseIterable {
    case systemData
    case developer
    case applications
    case photos
    case documents
    case mail
    case messages

    public var localizedTitle: String {
        switch self {
        case .systemData: return "시스템 데이터"
        case .developer: return "개발자"
        case .applications: return "응용 프로그램"
        case .photos: return "사진"
        case .documents: return "문서"
        case .mail: return "Mail"
        case .messages: return "메시지"
        }
    }

    /// 홈 기준 상대 경로 묶음이 어느 칸으로 세어지는지.
    ///
    /// macOS 가 정확히 어떻게 세는지는 공개돼 있지 않다. 이건 관찰에 기반한 근사치다.
    /// 그래서 화면에서도 "대략" 이라고 말해야 한다 — 시스템 설정 숫자와 딱 맞지 않을 수 있다.
    public static func forHomeBucket(_ bucket: String) -> MacOSStorageCategory {
        if bucket.hasPrefix("Library/Developer") { return .developer }
        if bucket.hasPrefix("Library/Mail") { return .mail }
        if bucket.hasPrefix("Library/Messages") { return .messages }
        if bucket == "Pictures" { return .photos }
        if bucket == "Applications" { return .applications }
        // ~/Library 의 나머지는 전부 시스템 데이터로 잡힌다.
        if bucket.hasPrefix("Library") { return .systemData }
        // 홈 아래의 그 밖의 폴더는 사용자 파일이라 '문서' 로 세어진다.
        return .documents
    }

    /// 홈 밖 절대 경로가 어느 칸으로 세어지는지.
    public static func forAbsolutePath(_ path: String) -> MacOSStorageCategory {
        if path.hasPrefix("/Applications") { return .applications }
        if path.hasPrefix("/Library/Developer") { return .developer }
        return .systemData
    }
}
