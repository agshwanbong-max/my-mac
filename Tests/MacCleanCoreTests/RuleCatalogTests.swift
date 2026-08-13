import XCTest
@testable import MacCleanCore

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

    /// 모든 규칙은 사람에게 보여줄 설명을 갖고 있어야 한다.
    func testEveryRuleExplainsItself() {
        for rule in rules {
            XCTAssertFalse(rule.title.isEmpty, "'\(rule.id)' 에 제목이 없습니다")
            XCTAssertFalse(rule.explanation.isEmpty, "'\(rule.id)' 에 설명이 없습니다")
            XCTAssertFalse(rule.consequence.isEmpty, "'\(rule.id)' 에 '지우면 어떻게 되는지' 설명이 없습니다")
        }
    }

    /// 와일드카드는 최대 하나만 허용한다 (스캐너가 그 이상은 처리하지 않는다).
    func testAtMostOneWildcardPerRule() {
        for rule in rules {
            let count = rule.path.filter { $0 == "*" }.count
            XCTAssertLessThanOrEqual(count, 1, "'\(rule.id)' 경로에 와일드카드가 둘 이상입니다")
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

    func testLibraryIsSplitOneLevelDeeper() {
        XCTAssertEqual(bucket("/Users/tester/Library/Developer/Xcode/a"), "Library/Developer")
        XCTAssertEqual(bucket("/Users/tester/Library/Application Support/App/x"), "Library/Application Support")
    }

    func testFileDirectlyInLibraryFallsBackToLibrary() {
        XCTAssertEqual(bucket("/Users/tester/Library/loose.txt"), "Library")
    }

    func testPathsOutsideHomeAreIgnored() {
        XCTAssertNil(bucket("/Applications/Xcode.app/x"))
        XCTAssertNil(bucket("/Users/other/Pictures/a.jpg"))
        XCTAssertNil(bucket(home))
    }
}
