import XCTest
@testable import MacCleanCore

/// 버전 비교와 업데이트 판정.
///
/// 여기가 틀리면 두 가지 중 하나가 일어난다.
/// 사용자가 첫 버전에 갇히거나, 최신 버전을 쓰는 사람에게 매일 업데이트 알림이 뜬다.
/// 둘 다 네트워크 없이 잡을 수 있는 문제라 순수 함수로 떼어놨다.
final class UpdateTests: XCTestCase {

    // MARK: - 파싱

    func testParsesPlainVersion() {
        XCTAssertEqual(AppVersion("1.2.3")?.components, [1, 2, 3])
    }

    /// 릴리스 태그는 `v` 가 붙어서 온다. 그대로 넣어도 읽혀야 한다.
    func testStripsTagPrefixAndSuffix() {
        XCTAssertEqual(AppVersion("v0.1.0")?.components, [0, 1, 0])
        XCTAssertEqual(AppVersion("1.4.0-beta.2")?.components, [1, 4, 0])
        XCTAssertEqual(AppVersion("  2.0  ")?.components, [2, 0])
    }

    func testRejectsGarbage() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("최신"))
        XCTAssertNil(AppVersion("v"))
    }

    // MARK: - 비교

    func testOrdersByComponent() {
        XCTAssertLessThan(AppVersion("1.2.3")!, AppVersion("1.2.4")!)
        XCTAssertLessThan(AppVersion("1.2.9")!, AppVersion("1.3.0")!)
        XCTAssertLessThan(AppVersion("0.9.9")!, AppVersion("1.0.0")!)
    }

    /// `0.10.0` 이 `0.9.0` 보다 낮다고 판정하면 (문자열 비교의 전형적 실수)
    /// 열 번째 릴리스부터 아무도 업데이트를 못 받는다.
    func testTenIsGreaterThanNine() {
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("0.10.0")!)
        XCTAssertLessThan(AppVersion("1.9.0")!, AppVersion("1.10.0")!)
    }

    /// 자릿수가 다른 경우. `1.2` 와 `1.2.0` 은 같은 버전이다.
    func testPadsMissingComponentsWithZero() {
        XCTAssertEqual(AppVersion("1.2")!, AppVersion("1.2.0")!)
        XCTAssertEqual(AppVersion("1")!, AppVersion("1.0.0")!)
        XCTAssertLessThan(AppVersion("1.2")!, AppVersion("1.2.1")!)
    }

    // MARK: - 판정

    private func manifest(_ version: String) -> UpdateChecker.Manifest {
        UpdateChecker.Manifest(
            version: version,
            downloadURL: URL(string: "https://example.com/MacClean.dmg")!
        )
    }

    func testNewerVersionIsOffered() {
        guard case .available(let found) = UpdateChecker.compare(
            current: "0.1.0", manifest: manifest("0.2.0")
        ) else {
            return XCTFail("새 버전을 알려주지 않았습니다")
        }
        XCTAssertEqual(found.version, "0.2.0")
    }

    func testSameVersionIsUpToDate() {
        guard case .upToDate = UpdateChecker.compare(
            current: "0.1.0", manifest: manifest("0.1.0")
        ) else {
            return XCTFail("같은 버전인데 업데이트가 있다고 했습니다")
        }
    }

    /// 개발 중인 빌드가 릴리스보다 앞서 있을 수 있다.
    /// 이때 "예전 버전으로 돌아가세요" 라고 하면 안 된다.
    func testOlderManifestIsNotOffered() {
        guard case .upToDate = UpdateChecker.compare(
            current: "0.3.0", manifest: manifest("0.2.0")
        ) else {
            return XCTFail("배포본보다 새 빌드에 업데이트를 권했습니다")
        }
    }

    /// 안내문이 망가졌을 때 업데이트가 있다고 우기면 안 된다.
    /// 조용히 실패해야 한다.
    func testUnreadableVersionIsUnavailable() {
        guard case .unavailable = UpdateChecker.compare(
            current: "0.1.0", manifest: manifest("최신")
        ) else {
            return XCTFail("읽을 수 없는 버전을 판정해버렸습니다")
        }

        guard case .unavailable = UpdateChecker.compare(
            current: "", manifest: manifest("1.0.0")
        ) else {
            return XCTFail("현재 버전을 못 읽었는데 판정했습니다")
        }
    }

    // MARK: - 안내문 형식

    /// `publish.sh` 가 만드는 JSON 과 앱이 읽는 구조가 같아야 한다.
    /// 이게 어긋나면 릴리스를 올려도 아무도 업데이트를 못 받는다.
    func testDecodesManifestProducedByPublishScript() throws {
        let json = """
        {
          "version": "0.2.0",
          "downloadURL": "https://github.com/agshwanbong-max/my-mac/releases/download/v0.2.0/MacClean-0.2.0.dmg",
          "releaseNotesURL": "https://github.com/agshwanbong-max/my-mac/releases/tag/v0.2.0",
          "minimumSystemVersion": "13.0",
          "publishedAt": "2026-08-14T09:30:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(UpdateChecker.Manifest.self, from: json)

        XCTAssertEqual(manifest.version, "0.2.0")
        XCTAssertEqual(manifest.minimumSystemVersion, "13.0")
        XCTAssertNotNil(manifest.publishedAt)
        XCTAssertEqual(manifest.downloadURL.lastPathComponent, "MacClean-0.2.0.dmg")
    }

    /// 나중에 필드를 빼먹어도 앱이 죽지 않아야 한다. 필수는 두 개뿐이다.
    func testDecodesMinimalManifest() throws {
        let json = """
        {"version": "1.0.0", "downloadURL": "https://example.com/a.dmg"}
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(UpdateChecker.Manifest.self, from: json)
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertNil(manifest.releaseNotesURL)
        XCTAssertNil(manifest.publishedAt)
    }

    /// 앱이 들고 다니는 버전은 저장소 루트의 `VERSION` 파일에서 나온다
    /// (`build_app.sh` 가 읽어서 Info.plist 에 넣는다).
    /// 여기에 오타가 나면 업데이트 확인이 통째로 죽으므로 형식을 확인해 둔다.
    func testVersionFileIsParsable() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MacCleanCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // 저장소 루트
        let versionFile = root.appendingPathComponent("VERSION")

        let text = try String(contentsOf: versionFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertNotNil(AppVersion(text), "VERSION 파일을 버전으로 읽지 못했습니다: \(text)")
        XCTAssertEqual(
            AppVersion(text)?.components.count, 3,
            "VERSION 은 x.y.z 세 자리로 적어주세요: \(text)"
        )
    }
}
