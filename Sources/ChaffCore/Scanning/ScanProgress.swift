import Foundation

/// 검사 진행 상황.
///
/// 스캐너 단위로 센다. 스캐너들이 동시에 도는데 "지금 몇 %" 를 정확히 말할 방법이 없어서,
/// **끝난 개수**를 세는 쪽을 택했다. 거짓 없는 숫자다.
/// 대신 오래 걸리는 스캐너가 `detail` 로 자기 진행을 계속 알려주므로 화면이 멈춘 것처럼 보이지 않는다.
public struct ScanProgress: Sendable, Equatable {
    /// 끝난 스캐너 수.
    public let completed: Int
    /// 전체 스캐너 수.
    public let total: Int
    /// 지금 무슨 일이 벌어지는지. 오래 걸리는 스캐너가 수시로 갱신한다.
    public let detail: String

    public init(completed: Int, total: Int, detail: String) {
        self.completed = completed
        self.total = total
        self.detail = detail
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    public var isFinished: Bool { completed >= total }
}

/// 오래 걸리는 스캐너가 진행 상황을 흘려보내는 통로.
///
/// 스캐너가 UI 를 모르게 하려고 클로저 하나로 감쌌다.
public struct ScanProgressReporter: Sendable {
    private let handler: @Sendable (String) -> Void

    public init(_ handler: @escaping @Sendable (String) -> Void) {
        self.handler = handler
    }

    public func note(_ message: String) {
        handler(message)
    }

    /// 아무 데도 보내지 않는다. 테스트와 CLI 기본값.
    public static let silent = ScanProgressReporter { _ in }
}
