import XCTest
@testable import ChaffCore

/// 규칙 카탈로그가 지켜야 하는 불변식.
///
/// 새 규칙을 추가할 때 실수하면 여기서 걸린다.
final class RuleCatalogTests: XCTestCase {

    private let paths = UserPaths(home: URL(fileURLWithPath: "/Users/tester"))

    private var rules: [CleanupRule] { RuleCatalog.all(paths: paths) }

    func testRuleIdentifiersAreUnique() {
        let identifiers = rules.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "규칙 id 가 중복됩니다")
    }

    /// 규칙이 겨냥하는 경로가 보호 목록 안에 있으면 안 된다.
    /// (있어도 `PathGuard` 가 막지만, 그건 마지막 방어선이지 설계 의도가 아니다.)
    func testNoRuleTargetsProtectedPath() {
        let protected = ProtectedPaths(paths: paths)
        for rule in rules where rule.removal != .adviseOnly {
            // 와일드카드는 실제 경로가 아니므로 `*` 앞부분만 검사한다.
            let literal = rule.path.components(separatedBy: "*")[0]
            let url = paths.resolve(literal)
            if let hit = protected.matchedDenyRule(for: url) {
                XCTFail("규칙 '\(rule.id)' 이 보호 경로를 겨냥합니다: \(hit)")
            }
        }
    }

    /// 되돌릴 수 없는 삭제는 휴지통 비우기 하나뿐이어야 한다.
    func testPermanentDeleteIsLimitedToTrash() {
        let permanent = rules.filter { $0.removal == .permanentDelete }
        XCTAssertEqual(permanent.map(\.id), ["trash.user"],
                       "완전 삭제는 휴지통 비우기에만 허용됩니다")
    }

    /// 안내 등급과 안내 전용 처리 방식은 항상 같이 다녀야 한다.
    func testAdvisoryRulesNeverRemoveFiles() {
        for rule in rules {
            if rule.risk == .advisory {
                XCTAssertEqual(rule.removal, .adviseOnly, "'\(rule.id)' 는 안내 등급인데 파일을 지우려 합니다")
            }
            if rule.removal == .adviseOnly {
                XCTAssertEqual(rule.risk, .advisory, "'\(rule.id)' 는 안내 전용인데 위험 등급이 안내가 아닙니다")
            }
        }
    }

    /// 모든 규칙은 사람에게 보여줄 설명을 **모든 언어에서** 갖고 있어야 한다.
    ///
    /// 규칙 문구는 이제 `Localizable.strings` 에 있다. 규칙만 추가하고 문구를 안 넣으면
    /// 화면에 `rule.dev.newThing.title` 이 그대로 찍힌다.
    /// 조회가 키를 그대로 돌려준다는 건 번역이 없다는 뜻이므로, 그걸로 잡는다.
    func testEveryRuleExplainsItselfInEveryLanguage() throws {
        for language in L10n.bundle.localizations.filter({ $0 != "Base" }) {
            let url = try XCTUnwrap(
                L10n.bundle.url(
                    forResource: "Localizable", withExtension: "strings",
                    subdirectory: nil, localization: language
                ))
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])

            for rule in rules {
                for part in ["title", "explanation", "consequence"] {
                    let key = "rule.\(rule.textKey).\(part)"
                    let text = table[key]
                    XCTAssertNotNil(text, "[\(language)] \(key) 문구가 없습니다")
                    XCTAssertFalse(
                        text?.isEmpty ?? true,
                        "[\(language)] \(key) 문구가 비어 있습니다"
                    )
                }
            }
        }
    }

    /// 와일드카드는 최대 하나만 허용한다 (스캐너가 그 이상은 처리하지 않는다).
    func testAtMostOneWildcardPerRule() {
        for rule in rules {
            let count = rule.path.filter { $0 == "*" }.count
            XCTAssertLessThanOrEqual(count, 1, "'\(rule.id)' 경로에 와일드카드가 둘 이상입니다")
        }
    }

    /// Application Support 를 겨냥하는 규칙은 **명백한 캐시 폴더 이름**으로 끝나야 한다.
    /// 앱 데이터 폴더를 통째로 겨냥하면 로그인 상태와 로컬 문서가 날아간다.
    func testApplicationSupportRulesTargetOnlyCacheFolders() {
        let allowedLeaves: Set<String> = [
            "Cache", "Code Cache", "GPUCache", "DawnCache",
            "DawnGraphiteCache", "DawnWebGPUCache", "ShaderCache",
            "component_crx_cache", "blob_storage",
        ]
        let forbiddenLeaves: Set<String> = [
            "Local Storage", "IndexedDB", "Session Storage", "Preferences", "Cookies",
        ]

        // 캐시 폴더가 아닌데도 겨냥해도 되는 규칙은 여기 적고, 왜 괜찮은지 남긴다.
        // 목록에 없으면 테스트가 막는다 — 실수로 앱 데이터 폴더를 겨냥하는 걸 방지한다.
        let reviewedExceptions: Set<String> = [
            // 동영상 배경화면 .mov 파일만 겨냥한다. 다시 받을 수 있고 휴지통으로 간다.
            "wallpaper.aerialVideos",
        ]

        for rule in rules where rule.path.hasPrefix("Library/Application Support") {
            if reviewedExceptions.contains(rule.id) { continue }
            let leaf = String(rule.path.split(separator: "/").last ?? "")
            XCTAssertFalse(forbiddenLeaves.contains(leaf),
                           "'\(rule.id)' 이 앱 데이터 폴더를 겨냥합니다: \(leaf)")
            XCTAssertTrue(allowedLeaves.contains(leaf),
                          "'\(rule.id)' 의 대상 '\(leaf)' 이 캐시 폴더 허용 목록에 없습니다")
        }
    }

    /// 캐시 규칙에 나이 조건을 걸면 안 된다.
    ///
    /// 캐시는 늘 최근에 바뀐다 — 그게 캐시다. "3일 이내 변경됐으니 제외" 는
    /// 브라우저를 쓰는 한 브라우저 캐시를 영원히 숨긴다는 뜻이다.
    /// 실제로 그것 때문에 3.5GB 가 목록에 한 번도 안 떴다.
    /// 대신 '그 앱이 실행 중인가' 로 판단한다.
    func testCacheRulesDoNotFilterByAge() {
        let cacheRuleIDs = rules
            .filter { $0.category == .userCache || $0.category == .browser }
            .map { $0.id }
        XCTAssertFalse(cacheRuleIDs.isEmpty, "캐시 규칙이 하나도 없습니다 — 테스트가 무의미해집니다")

        for rule in rules where cacheRuleIDs.contains(rule.id) {
            XCTAssertEqual(rule.minimumAgeDays, 0,
                           "'\(rule.id)' 는 캐시 규칙인데 나이 조건이 걸려 있습니다. "
                           + "캐시는 늘 최근에 바뀌므로 그 조건은 항목을 영원히 숨깁니다.")
        }
    }

    /// `.review` 이상은 반드시 되돌릴 수 있는 방식이거나, 휴지통 비우기처럼 본질적으로 영구인 작업이어야 한다.
    func testReviewRulesUseTrash() {
        for rule in rules where rule.risk == .review && rule.id != "trash.user" {
            XCTAssertEqual(rule.removal, .trashItem, "'\(rule.id)' 는 확인 등급인데 휴지통을 쓰지 않습니다")
        }
    }
}

/// 자식 이름 매칭. 실제 검사에서 `Adobe Camera Raw 2` 가 차단 목록을 빠져나간 적이 있다.
final class ChildNameMatchingTests: XCTestCase {

    func testMatchesVersionedFolderNames() {
        XCTAssertTrue(RuleScanner.matches("Adobe Camera Raw 2", ["Adobe"]))
        XCTAssertTrue(RuleScanner.matches("Adobe Camera Raw", ["Adobe Camera Raw"]))
        XCTAssertTrue(RuleScanner.matches("com.adobe.lightroomCC", ["com.adobe.lightroom"]))
    }

    func testDoesNotMatchUnrelatedNames() {
        XCTAssertFalse(RuleScanner.matches("com.adobe.Photoshop", ["Adobe"]))
        XCTAssertFalse(RuleScanner.matches("SiriTT", ["SiriTTS"]))
        XCTAssertFalse(RuleScanner.matches("anything", []))
    }

    /// 비용이 큰 캐시는 전용 규칙이 있는 항목과 겹치면 안 된다.
    /// 겹치면 전용 규칙의 등급 판단이 중복 정리 과정에서 조용히 뒤집힌다.
    func testCostlyListDoesNotCollideWithDedicatedRules() {
        let paths = UserPaths(home: URL(fileURLWithPath: "/Users/tester"))
        let dedicatedPaths = Set(RuleCatalog.all(paths: paths).map { $0.path })

        for name in RuleCatalog.costlyCacheDirectories {
            let candidate = "Library/Caches/\(name)"
            // ms-playwright 는 전용 규칙도 .review 라 등급이 어긋나지 않는다. 나머지는 겹치면 안 된다.
            if name == "ms-playwright" { continue }
            XCTAssertFalse(dedicatedPaths.contains(candidate),
                           "'\(name)' 은 전용 규칙이 있는데 비용 목록에도 들어 있습니다")
        }
    }
}

final class ToolCommandTests: XCTestCase {

    func testAllowsSimctlDelete() {
        let command = ToolCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "ABC-123"])
        XCTAssertTrue(command.isAllowed)
    }

    func testAllowsSimctlDeleteUnavailable() {
        let command = ToolCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"])
        XCTAssertTrue(command.isAllowed)
    }

    func testRejectsArbitraryCommands() {
        XCTAssertFalse(ToolCommand(executable: "/bin/rm", arguments: ["-rf", "/"]).isAllowed)
        XCTAssertFalse(ToolCommand(executable: "/usr/bin/sudo", arguments: ["rm"]).isAllowed)
        XCTAssertFalse(ToolCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "erase", "all"]).isAllowed)
        XCTAssertFalse(ToolCommand(executable: "/usr/bin/xcrun", arguments: []).isAllowed)
    }

    func testShellRunnerRejectsUnknownExecutable() {
        let runner = ShellRunner()
        XCTAssertThrowsError(try runner.run(executable: "/bin/rm", arguments: ["-rf", "/tmp/x"]))
    }
}

final class DeduplicationTests: XCTestCase {

    private func finding(id: String, path: String, risk: RiskLevel = .safe, bytes: Int64 = 1_000) -> Finding {
        Finding(
            id: id,
            ruleID: id,
            category: .userCache,
            risk: risk,
            title: id,
            detail: "",
            consequence: "",
            path: URL(fileURLWithPath: path),
            reclaimableBytes: bytes,
            itemCount: 1,
            lastModified: nil,
            removal: .trashItem,
            constraints: RuleConstraints(allowedRoots: [], minimumDepth: 0)
        )
    }

    /// 조상 경로는 버리고 더 구체적인 후보만 남긴다.
    func testDropsAncestorOfAnotherFinding() {
        let result = ScanCoordinator.deduplicate([
            finding(id: "generic", path: "/Users/t/Library/Caches/Google"),
            finding(id: "specific", path: "/Users/t/Library/Caches/Google/Chrome"),
        ])
        XCTAssertEqual(result.map(\.id), ["specific"])
    }

    /// 같은 경로가 두 번 나오면 더 조심스러운 등급을 남긴다.
    func testKeepsHigherRiskOnPathCollision() {
        let result = ScanCoordinator.deduplicate([
            finding(id: "a", path: "/Users/t/Library/Caches/Thing", risk: .safe),
            finding(id: "b", path: "/Users/t/Library/Caches/Thing", risk: .review),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].risk, .review)
    }

    /// 안내 전용 항목은 겹쳐도 그대로 남는다 (파일을 건드리지 않으므로).
    func testAdvisoryFindingsSurvive() {
        var advisory = finding(id: "advice", path: "/Users/t/Movies/big.mov")
        advisory.removal = .adviseOnly
        advisory.risk = .advisory

        let result = ScanCoordinator.deduplicate([advisory])
        XCTAssertEqual(result.count, 1)
    }
}


/// 용량 분포 묶음 계산.
///
/// 실제 맥에서 홈 용량의 90% 가 `~/Library` 한 곳에 있었다.
/// 그걸 "Library 75GB" 한 줄로 보여주면 아무 도움이 안 되므로 Library 만 한 단계 더 쪼갠다.
final class SpaceBreakdownBucketTests: XCTestCase {

    private let home = "/Users/tester"

    private func bucket(_ path: String) -> String? {
        SpaceBreakdownScanner.bucket(for: URL(fileURLWithPath: path), homePath: home)
    }

    func testTopLevelFolderBecomesItsOwnBucket() {
        XCTAssertEqual(bucket("/Users/tester/Pictures/a/b.jpg"), "Pictures")
        XCTAssertEqual(bucket("/Users/tester/Downloads/x.dmg"), "Downloads")
    }

    /// Application Support / Developer 는 안에서 앱별로 또 나뉜다.
    /// 한 덩어리로 보여주면 "Application Support 38GB" 라는 쓸모없는 한 줄이 된다.
    func testContainerFoldersAreSplitTwoLevelsDeep() {
        XCTAssertEqual(bucket("/Users/tester/Library/Developer/Xcode/a"), "Library/Developer/Xcode")
        XCTAssertEqual(bucket("/Users/tester/Library/Application Support/Claude/x"),
                       "Library/Application Support/Claude")
        XCTAssertEqual(bucket("/Users/tester/Library/Containers/com.foo/Data/x"),
                       "Library/Containers/com.foo")
    }

    func testOtherLibraryFoldersStayAtOneLevel() {
        XCTAssertEqual(bucket("/Users/tester/Library/Caches/foo/bar"), "Library/Caches")
        XCTAssertEqual(bucket("/Users/tester/Library/Logs/a/b"), "Library/Logs")
    }

    /// 쪼갤 폴더인데 그 아래에 파일이 바로 있으면 한 단계로 돌아간다.
    func testFileDirectlyInSplitFolder() {
        XCTAssertEqual(bucket("/Users/tester/Library/Developer/loose.txt"), "Library/Developer")
    }

    /// 묶음은 폴더여야 한다. 파일 이름이 묶음 이름이 되면 안 된다.
    func testFileDirectlyInLibraryFallsBackToLibrary() {
        XCTAssertEqual(bucket("/Users/tester/Library/loose.txt"), "Library")
    }

    /// 홈 바로 아래 파일은 묶을 폴더가 없다.
    func testFileDirectlyInHomeHasNoBucket() {
        XCTAssertNil(bucket("/Users/tester/loose.txt"))
    }

    func testPathsOutsideHomeAreIgnored() {
        XCTAssertNil(bucket("/Applications/Xcode.app/x"))
        XCTAssertNil(bucket("/Users/other/Pictures/a.jpg"))
        XCTAssertNil(bucket(home))
    }
}


/// macOS 저장 공간 화면의 칸 매핑.
///
/// 이게 틀리면 "DeviceSupport 를 지웠는데 시스템 데이터가 그대로다" 같은 혼란이 그대로 남는다.
final class MacOSStorageCategoryTests: XCTestCase {

    /// 가장 헷갈렸던 지점. DeviceSupport 17GB 는 '시스템 데이터'가 아니라 '개발자'다.
    func testDeveloperFolderIsNotSystemData() {
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Library/Developer"), .developer)
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Library/Developer/Xcode"), .developer)
    }

    func testLibraryFoldersCountAsSystemData() {
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Library/Caches"), .systemData)
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Library/Application Support/Claude"), .systemData)
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Library/Containers/com.foo"), .systemData)
    }

    func testUserFoldersCountAsDocuments() {
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Downloads"), .documents)
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Desktop"), .documents)
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("myproject"), .documents)
    }

    func testDedicatedCategoriesAreNotSwallowedBySystemData() {
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Pictures"), .photos)
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Library/Mail"), .mail)
        XCTAssertEqual(MacOSStorageCategory.forHomeBucket("Library/Messages"), .messages)
    }

    func testAbsolutePathsOutsideHome() {
        XCTAssertEqual(MacOSStorageCategory.forAbsolutePath("/Applications/Xcode.app"), .applications)
        XCTAssertEqual(MacOSStorageCategory.forAbsolutePath("/Library/Caches"), .systemData)
        XCTAssertEqual(MacOSStorageCategory.forAbsolutePath("/private/var/folders"), .systemData)
    }
}
