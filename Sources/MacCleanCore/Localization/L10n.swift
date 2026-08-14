import Foundation

/// 화면에 보이는 모든 문자열은 여기를 지나간다.
///
/// **왜 코어에 두는가**
/// 문자열의 절반 이상이 코어에 있다 — 규칙 설명, 판정 이유, 건너뛴 까닭.
/// 앱과 코어가 각자 번역 파일을 갖게 하면 같은 말을 두 번 번역하게 되고,
/// 둘이 어긋나면 화면 안에서 용어가 갈린다. 카탈로그는 하나다.
///
/// **왜 SwiftUI 의 `LocalizedStringKey` 를 안 쓰는가**
/// `Text("검사 중")` 은 **메인 번들**에서 찾는다. 코어는 라이브러리라 자기 번들
/// (`Bundle.module`)에 리소스가 들어가므로 그 경로로는 못 찾는다.
/// CLI 와 테스트에서도 같은 문자열을 써야 하는데 거기엔 SwiftUI 자체가 없다.
/// 그래서 조회를 한 곳으로 모으고, `Text(L(...))` 처럼 이미 번역된 문자열을 넘긴다.
public enum L10n {

    /// 번역이 실제로 들어 있는 번들.
    ///
    /// `Bundle.module` 은 SPM 이 만들어 주는 접근자다. 앱 번들에서는
    /// `Contents/Resources/MacClean_MacCleanCore.bundle` 을 찾아낸다
    /// (`build_app.sh` 가 거기에 복사해 둔다).
    static let bundle: Bundle = .module

    /// 지금 화면에 쓰이는 언어. 진단용.
    public static var currentLanguage: String {
        bundle.preferredLocalizations.first ?? "ko"
    }

    /// 이 앱이 들고 있는 번역 목록.
    public static var availableLanguages: [String] {
        bundle.localizations.filter { $0 != "Base" }.sorted()
    }
}

/// 번역된 문자열을 가져온다.
///
/// 키를 못 찾으면 **키 자체**가 화면에 나온다. 일부러 그렇게 뒀다 —
/// 빈 문자열이나 한국어로 조용히 되돌아가면 번역 누락을 아무도 발견하지 못한다.
/// `scan.progress.title` 이 버튼에 찍혀 있으면 한 번 보고 바로 안다.
///
///     L("verdict.safe")
///     L("scan.found", 12, "4.7GB")
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = L10n.bundle.localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: .current, arguments: arguments)
}
