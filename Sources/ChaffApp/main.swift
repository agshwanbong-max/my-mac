import Foundation

// `@main` 대신 여기서 직접 시작한다.
// SPM 실행 타깃에서 `main.swift` 와 `@main` 은 같이 쓸 수 없기 때문이다.
#if os(macOS)
import AppKit

// SPM 으로 빌드한 실행 파일은 앱 번들 밖에서 실행될 수 있다.
// 그 경우 메뉴 막대와 창을 제대로 띄우려면 activation policy 를 직접 올려줘야 한다.
NSApplication.shared.setActivationPolicy(.regular)
ChaffApp.main()
#else
print("Chaff 는 macOS 전용입니다.")
#endif
