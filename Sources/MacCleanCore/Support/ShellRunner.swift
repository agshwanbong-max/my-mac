import Foundation

/// 외부 명령 실행기.
///
/// 안전 설계상 두 가지를 강제한다.
/// 1. **셸을 거치지 않는다.** `/bin/sh -c` 를 쓰지 않으므로 인자에 특수문자가 있어도 명령이 되지 않는다.
/// 2. **허용 목록에 있는 실행 파일만 부른다.** 그리고 그 목록에 `rm`, `sudo` 같은 건 없다.
public struct ShellRunner: Sendable {

    public struct Result: Sendable {
        public let exitCode: Int32
        public let standardOutput: String
        public let standardError: String

        public var succeeded: Bool { exitCode == 0 }
    }

    public enum RunError: Error, LocalizedError {
        case executableNotAllowed(String)
        case executableMissing(String)
        case launchFailed(String)
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .executableNotAllowed(let path):
                return L("shell.notAllowed", path)
            case .executableMissing(let path):
                return L("shell.notFound", path)
            case .launchFailed(let message):
                return L("shell.failed", message)
            case .timedOut:
                return L("shell.timeout")
            }
        }
    }

    /// 이 앱이 부를 수 있는 실행 파일 전부. 여기 없으면 실행되지 않는다.
    /// 전부 정보 조회용이거나(`tmutil list`, `simctl list`),
    /// 명확히 범위가 좁은 삭제(`simctl delete`)다. `sudo` 는 목록에 없다.
    public static let allowedExecutables: Set<String> = [
        "/usr/bin/tmutil",
        "/usr/bin/xcrun",
        "/usr/sbin/system_profiler",
    ]

    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 20
    ) throws -> Result {
        guard ShellRunner.allowedExecutables.contains(executable) else {
            throw RunError.executableNotAllowed(executable)
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw RunError.executableMissing(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw RunError.launchFailed(error.localizedDescription)
        }

        // 파이프 버퍼가 가득 차서 자식이 멈추는 걸 막으려면 먼저 다 읽고 나서 기다려야 한다.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            throw RunError.timedOut
        }

        return Result(
            exitCode: process.terminationStatus,
            standardOutput: String(data: outData, encoding: .utf8) ?? "",
            standardError: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
