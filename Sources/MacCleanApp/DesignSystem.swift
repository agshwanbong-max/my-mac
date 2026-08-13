#if os(macOS)
import MacCleanCore
import SwiftUI

/// macOS 26 (Tahoe) 의 Liquid Glass API 를 쓰는 **유일한 파일**.
///
/// 일부러 한 곳에 몰아뒀다. 이유가 두 가지다.
/// 1. macOS 26 미만에서는 그 API 가 없다. 폴백을 한 군데서만 관리하면 된다.
/// 2. API 이름이 어긋나 빌드가 깨져도 고칠 곳이 이 파일 하나다.
///
/// 나머지 뷰들은 여기 정의된 의미 기반 modifier(`glassPanel`, `primaryAction` …)만 쓴다.
enum Design {
    /// 화면 여백 기준값. 전부 4의 배수로 맞춰 리듬을 만든다.
    static let gutter: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    static let panelRadius: CGFloat = 16
    static let barRadius: CGFloat = 6
}

// MARK: - Liquid Glass (macOS 26+) · 이하 버전은 머티리얼로 폴백

extension View {

    /// 떠 있는 패널. macOS 26 에서는 유리, 그 이하에서는 머티리얼.
    @ViewBuilder
    func glassPanel(radius: CGFloat = Design.panelRadius) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }

    /// 주 동작 버튼 (정리 실행).
    @ViewBuilder
    func primaryAction() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// 보조 동작 버튼 (미리보기, 다시 검사).
    @ViewBuilder
    func secondaryAction() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// 여러 유리 요소를 한 덩어리로 묶어 서로 자연스럽게 섞이게 한다 (macOS 26+).
/// 그 이하에서는 그냥 통과시킨다.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - 카테고리 시각 언어

extension FindingCategory {

    var symbolName: String {
        switch self {
        case .systemDataDiagnosis: return "stethoscope"
        case .systemData: return "internaldrive"
        case .spaceBreakdown: return "chart.pie"
        case .trash: return "trash"
        case .userCache: return "shippingbox"
        case .logs: return "doc.text"
        case .xcode: return "hammer"
        case .simulators: return "iphone.gen3"
        case .developerTooling: return "terminal"
        case .nodeModules: return "cube.box"
        case .browser: return "safari"
        case .mail: return "envelope"
        case .iosBackup: return "externaldrive.badge.icloud"
        case .downloads: return "arrow.down.circle"
        case .largeFiles: return "doc.richtext"
        case .manualSelection: return "hand.point.up.left"
        }
    }

    /// 저장 공간 막대와 사이드바에서 쓰는 색. 시스템 팔레트만 쓴다 (다크 모드·접근성 대응).
    var tint: Color {
        switch self {
        case .systemDataDiagnosis: return .orange
        case .systemData: return .orange
        case .spaceBreakdown: return .blue
        case .trash: return .gray
        case .userCache: return .teal
        case .logs: return .brown
        case .xcode: return .blue
        case .simulators: return .indigo
        case .developerTooling: return .purple
        case .nodeModules: return .green
        case .browser: return .cyan
        case .mail: return .mint
        case .iosBackup: return .pink
        case .downloads: return .yellow
        case .largeFiles: return .red
        case .manualSelection: return .purple
        }
    }
}

extension DeletionVerdict {
    var tint: Color {
        switch self {
        case .safe: return .green
        case .checkFirst: return .orange
        case .keep: return .red
        }
    }

    var symbolName: String {
        switch self {
        case .safe: return "checkmark.circle.fill"
        case .checkFirst: return "exclamationmark.circle.fill"
        case .keep: return "hand.raised.fill"
        }
    }
}

extension RiskLevel {
    var tint: Color {
        switch self {
        case .safe: return .green
        case .review: return .orange
        case .advisory: return .secondary
        }
    }
}

// MARK: - 스캐너 진행 표시용 이름

enum ScannerLabel {
    static func text(for identifier: String) -> String {
        switch identifier {
        case "systemData": return "시스템 데이터 진단 중…"
        case "rules": return "캐시와 로그를 훑는 중…"
        case "simulators": return "시뮬레이터를 확인하는 중…"
        case "iosBackup": return "기기 백업을 확인하는 중…"
        case "nodeModules": return "프로젝트 폴더를 살펴보는 중…"
        case "spaceBreakdown": return "홈 전체를 훑는 중… (수십 초 걸립니다)"
        case "systemArea": return "홈 밖(앱·시스템 폴더)을 재는 중…"
        default: return "검사 중…"
        }
    }
}
#endif
