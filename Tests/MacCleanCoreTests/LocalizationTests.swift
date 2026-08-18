import XCTest
@testable import MacCleanCore

/// 번역 카탈로그가 지켜야 하는 불변식.
///
/// 언어를 늘리면 사람이 못 지키는 규칙이 생긴다 — 키를 하나 추가하고 한 언어에만 넣는 것.
/// 그러면 그 언어 사용자 화면에 `verdict.safe.title` 같은 키 이름이 그대로 찍힌다.
/// 조용히 한국어로 되돌아가는 것보다는 낫지만, 발견은 여기서 하는 게 훨씬 싸다.
final class LocalizationTests: XCTestCase {

    /// 한국어가 원본이다. 나머지는 전부 여기에 맞춘다.
    private let base = "ko"

    private func table(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            L10n.bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: language
            ),
            "\(language) 번역 파일을 찾지 못했습니다"
        )
        return try XCTUnwrap(
            NSDictionary(contentsOf: url) as? [String: String],
            "\(language) 번역 파일을 읽지 못했습니다 (형식 오류일 수 있습니다)"
        )
    }

    private var languages: [String] {
        L10n.bundle.localizations.filter { $0 != "Base" }.sorted()
    }

    func testShipsMoreThanOneLanguage() {
        XCTAssertTrue(languages.contains(base), "원본 언어(\(base))가 번들에 없습니다")
        XCTAssertGreaterThan(languages.count, 1, "번역이 하나도 실리지 않았습니다")
    }

    func testEveryLanguageHasEveryKey() throws {
        let baseKeys = Set(try table(base).keys)
        XCTAssertFalse(baseKeys.isEmpty, "원본 카탈로그가 비어 있습니다")

        for language in languages where language != base {
            let keys = Set(try table(language).keys)

            let missing = baseKeys.subtracting(keys).sorted()
            XCTAssertTrue(missing.isEmpty, "\(language) 에 빠진 키: \(missing)")

            // 남은 키도 잡는다. 원본에서 지운 문자열이 번역에만 남아 있으면
            // 다음 사람이 그게 아직 쓰이는 줄 알고 고친다.
            let extra = keys.subtracting(baseKeys).sorted()
            XCTAssertTrue(extra.isEmpty, "\(language) 에만 있는 키: \(extra)")
        }
    }

    /// 서식 지정자가 어긋나면 **앱이 죽는다.**
    ///
    /// `String(format:)` 은 `%@` 자리에 정수를 넣으면 그 값을 포인터로 읽는다.
    /// 번역자가 `%d` 를 `%@` 로 잘못 옮기면 그 언어에서만 크래시가 나고,
    /// 한국어로 개발하는 동안에는 절대 재현되지 않는다.
    func testFormatSpecifiersMatchTheOriginal() throws {
        let baseTable = try table(base)

        for language in languages where language != base {
            let translated = try table(language)
            for (key, original) in baseTable {
                guard let text = translated[key] else { continue }
                XCTAssertEqual(
                    specifiers(in: original), specifiers(in: text),
                    "[\(language)] \(key) 의 서식 지정자가 원본과 다릅니다"
                )
            }
        }
    }

    /// 번역이 통째로 비어 있는 항목을 잡는다. 빈 문자열은 화면에서 그냥 사라진다.
    func testNoEmptyTranslations() throws {
        for language in languages {
            for (key, value) in try table(language) {
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "[\(language)] \(key) 의 번역이 비어 있습니다"
                )
            }
        }
    }

    /// 번역하다 원문이 섞여 들어간 것을 잡는다.
    ///
    /// 실제로 일본어 문장 안에 한글 한 글자가 남은 적이 있다("%d 日경過").
    /// 한 글자라 눈으로는 안 보이고, 그 언어를 읽는 사람만 이상하게 여긴다.
    /// 한국어가 원본이라 이 방향의 오염만 확인하면 된다.
    func testTranslationsContainNoLeftoverKorean() throws {
        let hangul = try NSRegularExpression(pattern: "[가-힣]")

        for language in languages where language != base {
            for (key, value) in try table(language) {
                let range = NSRange(value.startIndex..., in: value)
                XCTAssertNil(
                    hangul.firstMatch(in: value, range: range),
                    "[\(language)] \(key) 에 한국어가 남아 있습니다: \(value)"
                )
            }
        }
    }

    /// 코드가 실제로 부르는 키가 카탈로그에 있는지.
    ///
    /// 소스를 직접 읽어서 확인한다. `L("...")` 는 컴파일러가 검사해 주지 않으므로,
    /// 오타가 나면 화면에 나오기 전까지 아무도 모른다.
    func testEveryKeyUsedInSourceExists() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        let baseKeys = Set(try table(base).keys)
        var used = Set<String>()

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                // 문서 주석 안의 사용 예시는 실제 호출이 아니다.
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("///") { continue }
                used.formUnion(Self.callPattern.matches(in: String(line)))
            }
        }

        XCTAssertFalse(used.isEmpty, "소스에서 L(\"…\") 호출을 하나도 찾지 못했습니다")

        let unknown = used.subtracting(baseKeys).sorted()
        XCTAssertTrue(unknown.isEmpty, "카탈로그에 없는 키를 부르고 있습니다: \(unknown)")
    }

    // MARK: -

    private static let callPattern = Pattern(#"\bL\("([A-Za-z0-9._]+)"#)

    /// `%@`, `%d`, `%1$@` 같은 것만 뽑아낸다. 위치 지정자까지 포함해 비교해야
    /// 어순이 다른 언어에서 인자가 뒤바뀌는 걸 잡을 수 있다.
    private func specifiers(in text: String) -> [String] {
        Pattern(#"%(?:\d+\$)?[-+ #0]*[0-9.]*[@dfsu]"#).matches(in: text).sorted()
    }
}

/// 정규식 한 줄짜리 도우미. 테스트에서만 쓴다.
private struct Pattern {
    private let regex: NSRegularExpression

    init(_ pattern: String) {
        // 테스트 안에서만 쓰는 리터럴 패턴이라 실패하면 즉시 알아야 한다.
        regex = try! NSRegularExpression(pattern: pattern)
    }

    /// 캡처 그룹이 있으면 그 값을, 없으면 매치 전체를 돌려준다.
    func matches(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let target = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard let swiftRange = Range(target, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
