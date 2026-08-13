import XCTest
@testable import MacCleanCore

/// 판정 로직.
///
/// 여기서 확인하는 건 "정답을 맞히는가" 가 아니라 **"애매할 때 안전한 쪽으로 기우는가"** 다.
/// 판단 재료가 부족하면 언제나 보관 쪽으로 가야 한다.
final class ImportanceResolveTests: XCTestCase {

    private func resolve(
        _ level: ImportanceLevel,
        _ recoverability: Recoverability,
        size: Int64 = 1_000_000
    ) -> ImportanceAssessment {
        ImportanceAssessor.resolve(level: level, recoverability: recoverability, signals: [], sizeBytes: size)
    }

    func testDisposableIsAlwaysSafe() {
        XCTAssertEqual(resolve(.disposable, .regenerates).verdict, .safe)
        XCTAssertEqual(resolve(.disposable, .unknown).verdict, .safe)
    }

    func testCriticalIsAlwaysKeep() {
        for recoverability in Recoverability.allCases {
            XCTAssertEqual(resolve(.critical, recoverability).verdict, .keep,
                           "자격 증명은 \(recoverability) 여도 보관해야 합니다")
        }
    }

    /// 직접 만든 것인데 사본을 못 찾았으면 보관이다.
    func testPersonalWithoutCopyIsKeep() {
        XCTAssertEqual(resolve(.personal, .unknown).verdict, .keep)
        XCTAssertEqual(resolve(.personal, .onlyCopy).verdict, .keep)
    }

    /// 직접 만든 것이라도 다른 데 있으면 결정할 수 있다.
    func testPersonalWithCopyIsCheckFirst() {
        XCTAssertEqual(resolve(.personal, .inVersionControl).verdict, .checkFirst)
        XCTAssertEqual(resolve(.personal, .syncedElsewhere).verdict, .checkFirst)
    }

    /// **가장 중요한 규칙.** 다시 구할 수 있어 보여도 사본을 못 찾았으면 보관이다.
    /// 별것 아닌 파일이라도 세상에 하나뿐이면 지우면 안 된다.
    func testReplaceableButOnlyCopyIsKeep() {
        XCTAssertEqual(resolve(.replaceable, .onlyCopy).verdict, .keep)
    }

    func testCostMentionsSizeForRedownload() {
        let assessment = resolve(.replaceable, .redownloadable, size: 2_000_000_000)
        XCTAssertTrue(assessment.cost.contains("GB"), "재다운로드 대가에 크기가 들어가야 합니다: \(assessment.cost)")
    }

    /// 판정에는 언제나 사람이 읽을 결론과 대가가 붙어야 한다.
    func testEveryOutcomeExplainsItself() {
        for level in ImportanceLevel.allCases {
            for recoverability in Recoverability.allCases {
                let assessment = resolve(level, recoverability)
                XCTAssertFalse(assessment.headline.isEmpty, "\(level)/\(recoverability) 에 결론이 없습니다")
                XCTAssertFalse(assessment.cost.isEmpty, "\(level)/\(recoverability) 에 대가 설명이 없습니다")
            }
        }
    }
}

/// 실제 파일을 놓고 판정을 확인한다.
final class ImportanceAssessorTests: XCTestCase {

    private var home: URL!
    private var paths: UserPaths!
    private var assessor: ImportanceAssessor!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("macclean-importance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        home = base.resolvingSymlinksInPath().standardizedFileURL
        paths = UserPaths(home: home)
        assessor = ImportanceAssessor(paths: paths)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func makeFile(_ relative: String, bytes: Int = 1024) throws -> URL {
        let url = paths.resolve(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0, count: bytes).write(to: url)
        return url
    }

    func testCredentialIsKeep() throws {
        let url = try makeFile("work/server.pem")
        XCTAssertEqual(assessor.assess(url).verdict, .keep)
    }

    func testFileInSSHFolderIsKeep() throws {
        let url = try makeFile(".ssh/id_ed25519")
        let assessment = assessor.assess(url)
        XCTAssertEqual(assessment.verdict, .keep)
        XCTAssertEqual(assessment.level, .critical)
    }

    func testBuildOutputIsSafe() throws {
        let url = try makeFile("Projects/App/DerivedData/Build/output.o")
        let assessment = assessor.assess(url)
        XCTAssertEqual(assessment.verdict, .safe)
        XCTAssertEqual(assessment.recoverability, .regenerates)
    }

    func testNodeModulesIsSafe() throws {
        let url = try makeFile("Projects/App/node_modules/left-pad/index.js")
        XCTAssertEqual(assessor.assess(url).verdict, .safe)
    }

    /// 문서 폴더의 작업 파일은 사본을 못 찾으면 보관이다.
    func testAuthoredDocumentIsKeep() throws {
        let url = try makeFile("Documents/제안서.psd")
        let assessment = assessor.assess(url)
        XCTAssertEqual(assessment.verdict, .keep)
        XCTAssertEqual(assessment.level, .personal)
    }

    /// 원격이 없는 git 저장소 = 이 맥에만 있는 것.
    func testRepositoryWithoutRemoteIsKeep() throws {
        let url = try makeFile("code/myapp/src/main.swift")
        try FileManager.default.createDirectory(
            at: paths.resolve("code/myapp/.git"), withIntermediateDirectories: true
        )
        try "[core]\n\trepositoryformatversion = 0\n".write(
            to: paths.resolve("code/myapp/.git/config"), atomically: true, encoding: .utf8
        )

        let assessment = assessor.assess(url)
        XCTAssertEqual(assessment.recoverability, .onlyCopy)
        XCTAssertEqual(assessment.verdict, .keep)
    }

    /// 원격이 있으면 되찾을 수 있으므로 결정할 수 있다.
    func testRepositoryWithRemoteIsRecoverable() throws {
        let url = try makeFile("code/myapp/src/main.swift")
        try FileManager.default.createDirectory(
            at: paths.resolve("code/myapp/.git"), withIntermediateDirectories: true
        )
        try "[remote \"origin\"]\n\turl = git@github.com:me/app.git\n".write(
            to: paths.resolve("code/myapp/.git/config"), atomically: true, encoding: .utf8
        )

        let assessment = assessor.assess(url)
        XCTAssertEqual(assessment.recoverability, .inVersionControl)
        XCTAssertEqual(assessment.verdict, .checkFirst)
    }

    func testInstallerIsCheckFirst() throws {
        let url = try makeFile("Downloads/Installer.dmg")
        let assessment = assessor.assess(url)
        XCTAssertEqual(assessment.verdict, .checkFirst)
        XCTAssertEqual(assessment.recoverability, .redownloadable)
    }

    /// 클라우드 폴더는 "여기서 지우면 다른 데서도 사라진다" 는 사실을 반드시 말해야 한다.
    func testCloudFolderIsFlagged() throws {
        let url = try makeFile("Library/Mobile Documents/com~apple~CloudDocs/메모.txt")
        let assessment = assessor.assess(url)
        XCTAssertEqual(assessment.recoverability, .syncedElsewhere)
        XCTAssertTrue(assessment.cost.contains("다른 기기") || assessment.cost.contains("클라우드"),
                      "클라우드 동기화 경고가 대가 설명에 있어야 합니다: \(assessment.cost)")
    }

    /// 판정에는 근거가 하나라도 붙어야 한다. 근거 없는 판정은 사용자가 검증할 수 없다.
    func testAssessmentAlwaysCarriesEvidence() throws {
        let url = try makeFile("Documents/보고서.docx")
        XCTAssertFalse(assessor.assess(url).signals.isEmpty)
    }
}

/// 중복 파일 판정.
///
/// 중복 삭제는 이 앱에서 가장 위험한 동작이다 — 사용자 문서를 건드린다.
/// 안전의 근거는 "지워도 되는 파일이라서" 가 아니라 **"똑같은 사본이 남아서"** 다.
/// 그 근거가 실제로 성립하는지를 여기서 확인한다.
final class DuplicateKeeperTests: XCTestCase {

    private let paths = UserPaths(home: URL(fileURLWithPath: "/Users/tester"))

    private func url(_ relative: String) -> URL {
        paths.resolve(relative)
    }

    /// 다운로드 폴더는 받은 사본이 쌓이는 곳이다. 원본일 가능성이 낮다.
    func testPrefersCopyOutsideDownloads() {
        let keeper = DuplicateScanner.chooseKeeper(
            from: [url("Downloads/보고서.pdf"), url("Documents/보고서.pdf")],
            paths: paths
        )
        XCTAssertEqual(keeper, url("Documents/보고서.pdf"))
    }

    /// 둘 다 같은 조건이면 얕은 쪽. 깊이 묻힌 건 사본일 확률이 높다.
    func testPrefersShallowerPath() {
        let keeper = DuplicateScanner.chooseKeeper(
            from: [url("Documents/보관/2024/오래된/파일.zip"), url("Documents/파일.zip")],
            paths: paths
        )
        XCTAssertEqual(keeper, url("Documents/파일.zip"))
    }

    func testAlwaysReturnsOneOfTheInputs() {
        let candidates = [url("Downloads/a.bin"), url("Downloads/b.bin")]
        XCTAssertTrue(candidates.contains(DuplicateScanner.chooseKeeper(from: candidates, paths: paths)))
    }

    /// 검색 대상 폴더 밖의 파일은 후보가 되지 않는다.
    func testUserRootOnlyMatchesSearchedFolders() {
        XCTAssertEqual(DuplicateScanner.userRoot(of: url("Documents/a/b.pdf"), paths: paths),
                       url("Documents"))
        XCTAssertNil(DuplicateScanner.userRoot(of: url("Library/Caches/x.bin"), paths: paths))
        XCTAssertNil(DuplicateScanner.userRoot(of: URL(fileURLWithPath: "/tmp/x.bin"), paths: paths))
    }
}

/// 파일 해시.
final class FileHashTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macclean-hash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testIdenticalContentHashesTheSame() throws {
        let a = try write("a.txt", "같은 내용")
        let b = try write("b.txt", "같은 내용")
        XCTAssertEqual(FileHash.sha256(of: a), FileHash.sha256(of: b))
    }

    func testDifferentContentHashesDifferently() throws {
        let a = try write("a.txt", "내용 하나")
        let b = try write("b.txt", "내용 둘")
        XCTAssertNotEqual(FileHash.sha256(of: a), FileHash.sha256(of: b))
    }

    /// 앞부분만 같고 뒤가 다른 파일. 1차 통과는 통과하지만 전체 해시에서 갈려야 한다.
    func testPrefixHashCanCollideWhileFullHashDoesNot() throws {
        let shared = String(repeating: "동", count: 5000)
        let a = try write("a.txt", shared + "끝A")
        let b = try write("b.txt", shared + "끝B")

        XCTAssertEqual(FileHash.sha256(of: a, prefixBytes: 4096),
                       FileHash.sha256(of: b, prefixBytes: 4096))
        XCTAssertNotEqual(FileHash.sha256(of: a), FileHash.sha256(of: b))
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(FileHash.sha256(of: directory.appendingPathComponent("없음.txt")))
    }
}
