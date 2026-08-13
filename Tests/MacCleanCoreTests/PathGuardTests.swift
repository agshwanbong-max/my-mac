import XCTest
@testable import MacCleanCore

/// 관문 테스트.
///
/// 여기 있는 테스트가 이 프로젝트에서 가장 중요하다.
/// "실수로 지우면 안 되는 걸 지운다" 는 사고를 막는 게 전부 이 계층에 걸려 있다.
final class PathGuardTests: XCTestCase {

    private var home: URL!
    private var paths: UserPaths!
    private var guardian: PathGuard!

    override func setUpWithError() throws {
        // 임시 디렉터리는 보통 `/var/folders/…` 인데 이건 `/private/var/…` 로 가는 심볼릭 링크다.
        // 링크를 미리 풀어두지 않으면 관문의 링크 검사에 걸려 테스트가 엉뚱하게 실패한다.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("macclean-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        home = base.resolvingSymlinksInPath().standardizedFileURL
        paths = UserPaths(home: home)
        guardian = PathGuard(paths: paths)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - 도우미

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = paths.resolve(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func constraints(root: String, extraDepth: Int = 1) -> RuleConstraints {
        let rootURL = paths.resolve(root)
        return RuleConstraints(
            allowedRoots: [rootURL],
            minimumDepth: rootURL.standardizedFileURL.pathComponents.count - 1 + extraDepth
        )
    }

    // MARK: - 보호 경로

    func testDeniesDocuments() throws {
        let target = try makeDirectory("Documents/중요한폴더")
        let decision = guardian.evaluate(target, constraints: constraints(root: "Documents"))
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.gate, "G3")
    }

    func testDeniesDesktop() throws {
        let target = try makeDirectory("Desktop/작업")
        XCTAssertFalse(guardian.evaluate(target, constraints: constraints(root: "Desktop")).allowed)
    }

    func testDeniesICloudDrive() throws {
        let target = try makeDirectory("Library/Mobile Documents/com~apple~CloudDocs")
        XCTAssertFalse(guardian.evaluate(target, constraints: constraints(root: "Library/Mobile Documents")).allowed)
    }

    func testDeniesCloudStorageMounts() throws {
        let target = try makeDirectory("Library/CloudStorage/Dropbox-Personal")
        XCTAssertFalse(guardian.evaluate(target, constraints: constraints(root: "Library/CloudStorage")).allowed)
    }

    func testDeniesPathContainingGitDirectory() throws {
        let target = try makeDirectory("Library/Caches/myproject/.git/objects")
        XCTAssertFalse(guardian.evaluate(target, constraints: constraints(root: "Library/Caches", extraDepth: 1)).allowed)
    }

    func testDeniesInsideApplicationBundle() throws {
        let target = try makeDirectory("Library/Caches/Some.app/Contents")
        XCTAssertFalse(guardian.evaluate(target, constraints: constraints(root: "Library/Caches")).allowed)
    }

    func testDeniesPhotosLibrary() throws {
        let target = try makeDirectory("Library/Caches/My.photoslibrary/originals")
        XCTAssertFalse(guardian.evaluate(target, constraints: constraints(root: "Library/Caches")).allowed)
    }

    // MARK: - 허용

    func testAllowsCacheChild() throws {
        let target = try makeDirectory("Library/Caches/com.example.tool")
        let decision = guardian.evaluate(target, constraints: constraints(root: "Library/Caches"))
        XCTAssertTrue(decision.allowed, "거부 사유: [\(decision.gate)] \(decision.reason)")
    }

    func testAllowsDerivedDataChild() throws {
        let target = try makeDirectory("Library/Developer/Xcode/DerivedData/MyApp-abcdef")
        let decision = guardian.evaluate(target, constraints: constraints(root: "Library/Developer/Xcode/DerivedData"))
        XCTAssertTrue(decision.allowed, "거부 사유: [\(decision.gate)] \(decision.reason)")
    }

    // MARK: - 경계

    func testDeniesHomeItself() throws {
        let decision = guardian.evaluate(home, constraints: RuleConstraints(allowedRoots: [home], minimumDepth: 0))
        XCTAssertFalse(decision.allowed)
    }

    func testDeniesVolumeRoot() {
        let decision = guardian.evaluate(
            URL(fileURLWithPath: "/"),
            constraints: RuleConstraints(allowedRoots: [URL(fileURLWithPath: "/")], minimumDepth: 0)
        )
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.gate, "G1")
    }

    func testDeniesOutsideAllowedRoot() throws {
        let target = try makeDirectory("Library/Caches/com.example.tool")
        let other = constraints(root: "Library/Logs")
        let decision = guardian.evaluate(target, constraints: other)
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.gate, "G4")
    }

    func testDeniesTooShallow() throws {
        let target = try makeDirectory("Library/Caches/com.example.tool")
        let strict = RuleConstraints(
            allowedRoots: [paths.resolve("Library/Caches")],
            minimumDepth: 999
        )
        let decision = guardian.evaluate(target, constraints: strict)
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.gate, "G5")
    }

    func testDeniesNonexistentPath() {
        let target = paths.resolve("Library/Caches/does-not-exist")
        let decision = guardian.evaluate(target, constraints: constraints(root: "Library/Caches"))
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.gate, "G2")
    }

    // MARK: - 심볼릭 링크

    func testDeniesSymbolicLink() throws {
        let real = try makeDirectory("Library/Caches/real-target")
        let link = paths.resolve("Library/Caches/link-to-target")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let decision = guardian.evaluate(link, constraints: constraints(root: "Library/Caches"))
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.gate, "G2")
    }

    // MARK: - 예외 (iOS 백업)

    func testExemptionOpensOnlyTheNamedPrefix() throws {
        let backupRoot = try makeDirectory("Library/Application Support/MobileSync/Backup")
        let device = try makeDirectory("Library/Application Support/MobileSync/Backup/00008030-ABC")

        // 예외 없이는 막힌다.
        let without = RuleConstraints(
            allowedRoots: [backupRoot],
            minimumDepth: backupRoot.pathComponents.count - 1 + 1
        )
        XCTAssertFalse(guardian.evaluate(device, constraints: without).allowed)

        // 그 접두사를 명시적으로 열면 통과한다.
        let with = RuleConstraints(
            allowedRoots: [backupRoot],
            minimumDepth: backupRoot.pathComponents.count - 1 + 1,
            exemptProtectedPrefix: backupRoot
        )
        let decision = guardian.evaluate(device, constraints: with)
        XCTAssertTrue(decision.allowed, "거부 사유: [\(decision.gate)] \(decision.reason)")
    }

    func testExemptionDoesNotOpenOtherProtectedPaths() throws {
        let backupRoot = paths.resolve("Library/Application Support/MobileSync/Backup")
        let documents = try makeDirectory("Documents/something")

        // 백업 폴더 예외를 들고 있어도 Documents 는 여전히 막힌다.
        let sneaky = RuleConstraints(
            allowedRoots: [paths.resolve("Documents")],
            minimumDepth: 0,
            exemptProtectedPrefix: backupRoot
        )
        XCTAssertFalse(guardian.evaluate(documents, constraints: sneaky).allowed)
    }

    func testExemptionCannotOpenNameBasedDenials() throws {
        let backupRoot = try makeDirectory("Library/Application Support/MobileSync/Backup")
        let gitInsideBackup = try makeDirectory("Library/Application Support/MobileSync/Backup/dev/.git")

        let with = RuleConstraints(
            allowedRoots: [backupRoot],
            minimumDepth: 0,
            exemptProtectedPrefix: backupRoot
        )
        // 접두사 예외는 이름 기반 차단(.git)까지 열어주지 않는다.
        XCTAssertFalse(guardian.evaluate(gitInsideBackup, constraints: with).allowed)
    }
}
