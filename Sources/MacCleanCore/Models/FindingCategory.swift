import Foundation

/// 결과를 사람이 이해할 수 있는 묶음으로 나눈다. UI 의 섹션 단위이기도 하다.
public enum FindingCategory: String, Codable, Sendable, CaseIterable {
    case systemDataDiagnosis   // "시스템 데이터"가 왜 큰지에 대한 진단 (스냅샷 등)
    case systemData            // macOS 가 '시스템 데이터' 로 세는 것들
    case spaceBreakdown        // 나머지 용량이 어디에 있는지 (정리 대상이 아니라 지도)
    case trash
    case userCache
    case logs
    case xcode
    case simulators
    case developerTooling
    case nodeModules
    case browser
    case mail
    case iosBackup
    case downloads
    case largeFiles
    case duplicates
    case manualSelection       // 사용자가 탐색기에서 직접 고른 것

    public var localizedTitle: String {
        switch self {
        case .systemDataDiagnosis: return "시스템 데이터 진단"
        case .systemData: return "시스템 데이터"
        case .spaceBreakdown: return "용량 분포"
        case .trash: return "휴지통"
        case .userCache: return "앱 캐시"
        case .logs: return "로그 · 진단 리포트"
        case .xcode: return "Xcode"
        case .simulators: return "iOS 시뮬레이터"
        case .developerTooling: return "개발 도구 캐시"
        case .nodeModules: return "오래된 node_modules"
        case .browser: return "브라우저 캐시"
        case .mail: return "메일 첨부 임시본"
        case .iosBackup: return "iPhone · iPad 백업"
        case .downloads: return "다운로드 폴더"
        case .largeFiles: return "대용량 파일"
        case .duplicates: return "중복 파일"
        case .manualSelection: return "직접 고른 항목"
        }
    }

    /// UI 정렬 순서. 진단이 항상 맨 위로 온다.
    public var sortOrder: Int {
        switch self {
        case .systemDataDiagnosis: return 0
        case .systemData: return 1
        case .spaceBreakdown: return 2
        case .trash: return 3
        case .xcode: return 4
        case .simulators: return 5
        case .iosBackup: return 6
        case .developerTooling: return 7
        case .nodeModules: return 8
        case .userCache: return 9
        case .browser: return 10
        case .logs: return 11
        case .mail: return 12
        case .downloads: return 13
        case .duplicates: return 14
        case .largeFiles: return 15
        case .manualSelection: return 16
        }
    }
}
